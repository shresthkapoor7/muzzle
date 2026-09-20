import AppKit
import MuzzleService

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let blocker = BlockerController(isDebugMode: DebugMode.isEnabled)
    private lazy var pokeAPIKeyStore = PokeAPIKeyStore()
    private lazy var pokeClient = PokeClient(apiKeyStore: pokeAPIKeyStore)
    private var statusItemController: StatusItemController?
    private var managementWindowController: ManagementWindowController?
    private var workContextAlert: NSAlert?
    private var unlockKey: String = ""
    private var bypassRequest: BypassRequest?
    private var isRequestingBypass = false
    private var bypassRequestSessionID: UUID?
    private var isSecondaryInstance = false
    private var isQuitAuthorized = false
    private let isDebugMode = DebugMode.isEnabled
    private var isCheckingForUpdates = false
    private var updateTimer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !isDebugMode else { return }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let runningCopies = NSRunningApplication.runningApplications(
            withBundleIdentifier: "local.muzzle.app"
        )

        guard let firstCopy = runningCopies.first(where: { $0.processIdentifier != ownPID }) else { return }
        isSecondaryInstance = true
        firstCopy.activate(options: [])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isSecondaryInstance else {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        blocker.onBypassRestoration = { [weak self] event in
            guard let self, !self.isDebugMode, !self.blocker.isTimedSession else { return }
            self.pokeClient.sendBypassRestoration(event) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, case .failure(let error) = result else { return }
                    self.blocker.present(error: error)
                }
            }
        }

        Task { @MainActor in
            do {
                try await blocker.load()
                if blocker.needsSystemReconciliation {
                    try await blocker.reconcileSystemState()
                }
                if !isDebugMode, !blocker.blockedDomains.isEmpty, !blocker.isTimedSession, !blocker.isBypassActive {
                    requestWorkContextForPokeDelivery()
                }
            } catch { blocker.present(error: error) }
        }

        if !isDebugMode {
            unlockKey = UnlockKey.make()
        }
        statusItemController = StatusItemController(
            blocker: blocker,
            isDebugMode: isDebugMode,
            onManage: { [weak self] in self?.showManagementWindow() },
            onEndSession: { [weak self] in self?.requestEndSession() },
            onBypass: { [weak self] in self?.requestBypass() },
            onRequestBypass: { [weak self] in self?.requestExtraBypass() },
            onRedeemBypass: { [weak self] in self?.redeemExtraBypass() },
            onRetrySystemUpdate: { [weak self] in self?.retrySystemUpdate() },
            onQuit: { [weak self] in self?.quitWhenInactive() },
            onCheckForUpdates: { [weak self] in self?.checkForUpdates(manual: true) }
        )

        if !isDebugMode {
            checkForUpdates(manual: false)
            updateTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkForUpdates(manual: false) }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (isSecondaryInstance || isQuitAuthorized || blocker.usesPrivilegedService) ? .terminateNow : .terminateCancel
    }

    private func checkForUpdates(manual: Bool) {
        guard !isCheckingForUpdates else { return }
        let defaults = UserDefaults.standard
        let lastCheckKey = "MuzzleLastSuccessfulUpdateCheck"
        if !manual, let last = defaults.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 86400 { return }
        isCheckingForUpdates = true
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        Task { @MainActor in
            defer { isCheckingForUpdates = false }
            do {
                let update = try await UpdateChecker().check(currentVersion: version)
                if !isDebugMode { defaults.set(Date(), forKey: lastCheckKey) }
                guard manual || update != nil else { return }
                let alert = NSAlert()
                if let update {
                    alert.messageText = "Muzzle \(update.version) is available"
                    alert.informativeText = "You’re running \(version). Download the DMG, then install it when your protection session has ended."
                    alert.addButton(withTitle: "Download Update")
                    alert.addButton(withTitle: "Later")
                    alert.addButton(withTitle: "Release Notes")
                    switch alert.runModal() {
                    case .alertFirstButtonReturn: NSWorkspace.shared.open(update.downloadURL)
                    case .alertThirdButtonReturn: NSWorkspace.shared.open(update.releaseURL)
                    default: break
                    }
                } else {
                    alert.messageText = "Muzzle is up to date"
                    alert.informativeText = "No newer stable release is available for version \(version)."
                    alert.runModal()
                }
            } catch {
                guard manual else { return }
                let alert = NSAlert()
                alert.messageText = "Couldn’t check for updates"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    private func showManagementWindow() {
        if managementWindowController == nil {
            managementWindowController = ManagementWindowController(
                blocker: blocker,
                isDebugMode: isDebugMode,
                pokeAPIKeyStore: pokeAPIKeyStore,
                onProtectionStarted: { [weak self] in self?.startProtectionSession() },
                onTestPoke: { [weak self] completion in self?.sendPokeConnectionTest(completion: completion) },
                onRetrySystemUpdate: { [weak self] in self?.retrySystemUpdate() },
                onInstallService: { [weak self] in self?.installBlockingService() }
            )
        }
        managementWindowController?.showWindow(nil)
        managementWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func deliverUnlockKeyToPoke(workingOn: String? = nil) {
        guard !isDebugMode else { return }
        if blocker.usesPrivilegedService {
            guard let token = pokeAPIKeyStore.apiKey() else { blocker.present(error: PokeClient.PokeError.missingAPIKey); return }
            performServiceDelivery(.deliverKey(token: token, context: workingOn))
            return
        }
        pokeClient.sendLockKey(unlockKey, workingOn: workingOn) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case let .failure(error) = result else { return }
                self.blocker.present(error: error)
            }
        }
    }

    private func sendPokeConnectionTest(completion: @escaping (Result<Void, Error>) -> Void) {
        pokeClient.sendConnectionTest(completion: completion)
    }

    private func startProtectionSession() {
        bypassRequest = nil
        guard !isDebugMode else { return }
        guard pokeAPIKeyStore.isConfigured else {
            blocker.present(error: PokeClient.PokeError.missingAPIKey)
            return
        }
        unlockKey = UnlockKey.make()
        DispatchQueue.main.async { [weak self] in
            self?.requestWorkContextForPokeDelivery()
        }
    }

    private func retrySystemUpdate() {
        Task { @MainActor in
            switch await blocker.retryPendingSystemUpdate() {
            case .none:
                return
            case let .protectionStarted(isTimed):
                if !isDebugMode, !isTimed {
                    startProtectionSession()
                }
            case let .bypassStarted(minutes, isTimed):
                if !isDebugMode, !isTimed {
                    sendBypassToPoke(minutes: minutes)
                }
            }
        }
    }

    private func requestBypass() {
        let alert = NSAlert()
        alert.icon = MuzzleIcon.alertImage()
        alert.messageText = "Start a bypass?"
        alert.informativeText = "Access is restored temporarily. Muzzle will block the website again when the time expires."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Start bypass")
        alert.addButton(withTitle: "Cancel")

        let durationForm = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 58))
        let durationLabel = NSTextField(labelWithString: "Bypass length")
        durationLabel.frame = NSRect(x: 0, y: 38, width: 300, height: 18)
        durationLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let durationField = NSTextField(frame: NSRect(x: 0, y: 2, width: 80, height: 28))
        durationField.stringValue = "5"
        durationField.alignment = .right
        durationField.placeholderString = "Minutes"
        durationField.setAccessibilityLabel("Bypass duration in minutes")

        let unitLabel = NSTextField(labelWithString: "minutes")
        unitLabel.frame = NSRect(x: 90, y: 7, width: 90, height: 18)
        unitLabel.font = .systemFont(ofSize: 13)
        unitLabel.textColor = .secondaryLabelColor

        durationForm.addSubview(durationLabel)
        durationForm.addSubview(durationField)
        durationForm.addSubview(unitLabel)
        alert.accessoryView = durationForm
        alert.window.initialFirstResponder = durationField

        while alert.runModal() == .alertFirstButtonReturn {
            let input = durationField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let minutes = Int(input), minutes > 0 else {
                alert.informativeText = "Enter a positive whole number of minutes. Muzzle will restore the current website block when this time ends."
                continue
            }

            Task { @MainActor in
                do {
                    try await blocker.startBypass(for: minutes)
                    if !isDebugMode, !blocker.isTimedSession {
                        sendBypassToPoke(minutes: minutes)
                    }
                    return
                } catch {
                    blocker.present(error: error)
                    return
                }
            }
            return
        }
    }

    private func requestExtraBypass() {
        guard !isDebugMode, !blocker.canQuit, !isRequestingBypass else { return }
        guard blocker.remainingBypasses < 3 else {
            showBypassMessage("You already have three bypasses available.")
            return
        }
        if blocker.usesPrivilegedService {
            guard let token = pokeAPIKeyStore.apiKey() else { blocker.present(error: PokeClient.PokeError.missingAPIKey); showManagementWindow(); return }
            isRequestingBypass = true
            performServiceDelivery(.requestExtra(token: token), extraBypass: true)
            return
        }
        let request = BypassRequest()
        bypassRequestSessionID = blocker.sessionID
        bypassRequest = request
        isRequestingBypass = true
        pokeClient.requestBypass(code: request.code) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRequestingBypass = false
                guard self.bypassRequest?.code == request.code,
                      self.bypassRequestSessionID == self.blocker.sessionID,
                      !self.blocker.canQuit else { return }
                switch result {
                case .success:
                    self.bypassRequest?.markDelivered()
                    self.showBypassMessage("Request sent to Poke. Enter the approval code within 15 minutes to add one bypass.")
                case .failure(let error):
                    self.bypassRequest = nil
                    self.blocker.present(error: error)
                    self.showManagementWindow()
                }
            }
        }
    }

    private func redeemExtraBypass() {
        guard !isDebugMode, !blocker.canQuit, !isRequestingBypass else { return }
        guard blocker.usesPrivilegedService || (bypassRequest != nil && bypassRequestSessionID == blocker.sessionID) else {
            showBypassMessage("Request an extra bypass from Poke first.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Enter bypass approval code"
        alert.informativeText = "This adds one bypass without ending protection."
        alert.addButton(withTitle: "Add bypass")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 28))
        field.placeholderString = "Six-digit code from Poke"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if blocker.usesPrivilegedService {
            let code = field.stringValue
            Task { @MainActor in
                do {
                    try await blocker.serviceCommand(.redeemExtra(code: code))
                    showBypassMessage("One extra bypass is available.")
                } catch { blocker.present(error: error); showManagementWindow() }
            }
            return
        }
        var request = bypassRequest
        guard request?.redeem(field.stringValue) == true else {
            bypassRequest = request
            showBypassMessage("That code is invalid, expired, or already used. After five attempts, request a new code.")
            return
        }
        do {
            try blocker.grantExtraBypass()
            bypassRequest = nil
            showBypassMessage("One extra bypass is available.")
        } catch {
            blocker.present(error: error)
            showManagementWindow()
        }
    }

    private func showBypassMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Extra bypass"
        alert.informativeText = message
        alert.runModal()
    }

    private func sendBypassToPoke(minutes: Int) {
        guard !isDebugMode else { return }
        pokeClient.sendBypass(minutes: minutes) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case let .failure(error) = result else { return }
                self.blocker.present(error: error)
            }
        }
    }

    private func requestWorkContextForPokeDelivery() {
        guard workContextAlert == nil else { return }

        showManagementWindow()
        guard let window = managementWindowController?.window else {
            deliverUnlockKeyToPoke()
            return
        }

        let alert = NSAlert()
        alert.icon = MuzzleIcon.alertImage()
        alert.messageText = "What are you working on?"
        alert.informativeText = "Optional — Muzzle will include this with the session key sent to Poke."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        field.placeholderString = "Optional"
        field.maximumNumberOfLines = 1
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.window.makeFirstResponder(field)
        workContextAlert = alert

        alert.beginSheetModal(for: window) { [weak self] _ in
            let workingOn = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            self?.workContextAlert = nil
            self?.deliverUnlockKeyToPoke(workingOn: workingOn.isEmpty ? nil : workingOn)
        }
    }

    private func quitWhenInactive() {
        guard blocker.canQuitApp else { return }
        isQuitAuthorized = true
        NSApp.terminate(nil)
    }

    private func requestEndSession() {
        if isDebugMode {
            Task { @MainActor in
                do {
                    try await blocker.endProtection()
                } catch {
                    blocker.present(error: error)
                }
            }
            return
        }

        let alert = NSAlert()
        alert.icon = MuzzleIcon.alertImage()
        alert.messageText = "End website blocking?"
        alert.informativeText = "Enter this session’s unlock key to remove Muzzle’s entries from your hosts file. Muzzle will remain available in the menu bar."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "End protection")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        field.placeholderString = "Six-digit session code"
        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        field.maximumNumberOfLines = 1
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.window.makeFirstResponder(field)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard blocker.usesPrivilegedService || field.stringValue == unlockKey else {
            let invalidAlert = NSAlert()
            invalidAlert.icon = MuzzleIcon.alertImage()
            invalidAlert.messageText = "That key does not match"
            invalidAlert.informativeText = "Muzzle will keep running."
            invalidAlert.alertStyle = .critical
            invalidAlert.runModal()
            return
        }

        let key = field.stringValue
        Task { @MainActor in
            do {
                try await blocker.endProtection(key: key)
                bypassRequest = nil
            } catch {
                blocker.present(error: error)
            }
        }
    }

    private func installBlockingService() {
        do {
            try BlockingServiceClient.install()
            Task { @MainActor in
                do { try await blocker.load() }
                catch { blocker.present(error: error); showManagementWindow() }
            }
        } catch { blocker.present(error: error); showManagementWindow() }
    }

    private func performServiceDelivery(_ command: ServiceCommand, extraBypass: Bool = false) {
        Task { @MainActor in
            defer { if extraBypass { isRequestingBypass = false } }
            do {
                try await blocker.serviceCommand(command)
                if extraBypass { showBypassMessage("Request sent to Poke. Enter the approval code within 15 minutes to add one bypass.") }
            } catch { blocker.present(error: error); showManagementWindow() }
        }
    }

}
