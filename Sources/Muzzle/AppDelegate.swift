import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let blocker = BlockerController()
    private let pokeClient = PokeClient()
    private var statusItemController: StatusItemController?
    private var managementWindowController: ManagementWindowController?
    private var workContextAlert: NSAlert?
    private var unlockKey: String = ""
    private var isSecondaryInstance = false
    private var isQuitAuthorized = false

    func applicationWillFinishLaunching(_ notification: Notification) {
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

        do {
            try blocker.load()
            if blocker.needsSystemReconciliation {
                try blocker.reconcileSystemState()
            }
        } catch {
            blocker.present(error: error)
        }

        unlockKey = UnlockKey.make()
        statusItemController = StatusItemController(
            blocker: blocker,
            onManage: { [weak self] in self?.showManagementWindow() },
            onEndSession: { [weak self] in self?.requestEndSession() },
            onBypass: { [weak self] in self?.requestBypass() },
            onRetrySystemUpdate: { [weak self] in self?.retrySystemUpdate() },
            onQuit: { [weak self] in self?.quitWhenInactive() }
        )

        if !blocker.blockedDomains.isEmpty, !blocker.isTimedSession, !blocker.isBypassActive {
            DispatchQueue.main.async { [weak self] in
                self?.requestWorkContextForPokeDelivery()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (isSecondaryInstance || isQuitAuthorized) ? .terminateNow : .terminateCancel
    }

    private func showManagementWindow() {
        if managementWindowController == nil {
            managementWindowController = ManagementWindowController(
                blocker: blocker,
                onProtectionStarted: { [weak self] in self?.startProtectionSession() },
                onRetrySystemUpdate: { [weak self] in self?.retrySystemUpdate() }
            )
        }
        managementWindowController?.showWindow(nil)
        managementWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func deliverUnlockKeyToPoke(workingOn: String? = nil) {
        pokeClient.sendLockKey(unlockKey, workingOn: workingOn) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case let .failure(error) = result else { return }
                self.blocker.present(error: error)
            }
        }
    }

    private func startProtectionSession() {
        unlockKey = UnlockKey.make()
        DispatchQueue.main.async { [weak self] in
            self?.requestWorkContextForPokeDelivery()
        }
    }

    private func retrySystemUpdate() {
        switch blocker.retryPendingSystemUpdate() {
        case .none:
            return
        case let .protectionStarted(isTimed):
            if !isTimed {
                startProtectionSession()
            }
        case let .bypassStarted(minutes, isTimed):
            if !isTimed {
                sendBypassToPoke(minutes: minutes)
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

            do {
                try blocker.startBypass(for: minutes)
                if !blocker.isTimedSession {
                    sendBypassToPoke(minutes: minutes)
                }
                return
            } catch {
                blocker.present(error: error)
                return
            }
        }
    }

    private func sendBypassToPoke(minutes: Int) {
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
        alert.informativeText = "Optional — Muzzle will include this with the new lock key sent to Poke."
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
        guard blocker.canQuit else { return }
        isQuitAuthorized = true
        NSApp.terminate(nil)
    }

    private func requestEndSession() {
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
        guard field.stringValue == unlockKey else {
            let invalidAlert = NSAlert()
            invalidAlert.icon = MuzzleIcon.alertImage()
            invalidAlert.messageText = "That key does not match"
            invalidAlert.informativeText = "Muzzle will keep running."
            invalidAlert.alertStyle = .critical
            invalidAlert.runModal()
            return
        }

        do {
            try blocker.endProtection()
        } catch {
            blocker.present(error: error)
        }
    }

}
