import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let blocker = BlockerController()
    private var statusItemController: StatusItemController?
    private var managementWindowController: ManagementWindowController?
    private var unlockKey: String = ""
    private var isTerminationAuthorized = false
    private var isSecondaryInstance = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let runningCopies = NSRunningApplication.runningApplications(
            withBundleIdentifier: "local.websiteblocker.app"
        )

        guard let firstCopy = runningCopies.first(where: { $0.processIdentifier != ownPID }) else { return }
        isSecondaryInstance = true
        firstCopy.activate(options: [])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isSecondaryInstance else {
            isTerminationAuthorized = true
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
            onEndSession: { [weak self] in self?.requestEndSession() }
        )

        if !blocker.blockedDomains.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.showUnlockKey()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isTerminationAuthorized ? .terminateNow : .terminateCancel
    }

    private func showManagementWindow() {
        if managementWindowController == nil {
            managementWindowController = ManagementWindowController(
                blocker: blocker,
                onProtectionStarted: { [weak self] in self?.showUnlockKey() }
            )
        }
        managementWindowController?.showWindow(nil)
        managementWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showUnlockKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Your session unlock key"
        alert.informativeText = "Store this six-digit code somewhere safe. It is required to end protection normally, and it is kept only for this running session.\n\n\(unlockKey)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Copy key")
        alert.addButton(withTitle: "Done")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(unlockKey, forType: .string)
        }
    }

    private func requestEndSession() {
        let alert = NSAlert()
        alert.messageText = "End website blocking?"
        alert.informativeText = "Enter this session’s unlock key to remove Website Blocker’s entries from your hosts file and quit."
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
            invalidAlert.informativeText = "Website Blocker will keep running."
            invalidAlert.alertStyle = .critical
            invalidAlert.runModal()
            return
        }

        do {
            try blocker.endProtection()
            isTerminationAuthorized = true
            NSApp.terminate(nil)
        } catch {
            blocker.present(error: error)
        }
    }

}
