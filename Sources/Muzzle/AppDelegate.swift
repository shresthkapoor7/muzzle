import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let blocker = BlockerController()
    private let pokeClient = PokeClient()
    private var statusItemController: StatusItemController?
    private var managementWindowController: ManagementWindowController?
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
            if !blocker.blockedDomains.isEmpty {
                try blocker.reconcileHostsFile()
            }
        } catch {
            blocker.present(error: error)
        }

        unlockKey = UnlockKey.make()
        statusItemController = StatusItemController(
            blocker: blocker,
            onManage: { [weak self] in self?.showManagementWindow() },
            onEndSession: { [weak self] in self?.requestEndSession() },
            onQuit: { [weak self] in self?.quitWhenInactive() }
        )

        if !blocker.blockedDomains.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.deliverUnlockKeyToPoke()
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
                onProtectionStarted: { [weak self] workingOn in self?.startProtectionSession(workingOn: workingOn) }
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

    private func startProtectionSession(workingOn: String?) {
        unlockKey = UnlockKey.make()
        deliverUnlockKeyToPoke(workingOn: workingOn)
    }

    private func quitWhenInactive() {
        guard blocker.blockedDomains.isEmpty else { return }
        isQuitAuthorized = true
        NSApp.terminate(nil)
    }

    private func requestEndSession() {
        let alert = NSAlert()
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
