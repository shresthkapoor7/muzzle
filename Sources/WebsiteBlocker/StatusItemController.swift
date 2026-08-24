import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let blocker: BlockerController
    private let onManage: () -> Void
    private let onEndSession: () -> Void
    private let statusItem: NSStatusItem
    private var blockerObservation: AnyCancellable?

    init(
        blocker: BlockerController,
        onManage: @escaping () -> Void,
        onEndSession: @escaping () -> Void
    ) {
        self.blocker = blocker
        self.onManage = onManage
        self.onEndSession = onEndSession
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        updateStatusButton()
        rebuildMenu()
        observeBlocker()
    }

    private func observeBlocker() {
        blockerObservation = blocker.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusButton()
                self?.rebuildMenu()
            }
        }
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        let isBlocking = !blocker.blockedDomains.isEmpty
        let symbolName = isBlocking ? "hand.raised.fill" : "circle"
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: isBlocking ? "Website Blocker is active" : "Website Blocker is inactive"
        )
        button.image?.isTemplate = true
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = isBlocking ? "Website Blocker: active" : "Website Blocker: inactive"
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let title = NSMenuItem(title: "Website Blocker", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let status = NSMenuItem(title: blocker.statusMessage, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let manageTitle = blocker.blockedDomains.isEmpty ? "Start blocking…" : "Manage protected websites…"
        menu.addItem(makeItem(manageTitle, action: #selector(manage)))
        menu.addItem(.separator())
        menu.addItem(makeItem("End protection with key…", action: #selector(endSession)))

        statusItem.menu = menu
    }

    private func makeItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func manage() { onManage() }
    @objc private func endSession() { onEndSession() }
}
