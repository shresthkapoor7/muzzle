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
        self.statusItem = NSStatusBar.system.statusItem(withLength: 78)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "Website Blocker")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.title = " BLOCK"
            button.toolTip = "Website Blocker"
        }
        rebuildMenu()
        observeBlocker()
    }

    private func observeBlocker() {
        blockerObservation = blocker.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.rebuildMenu()
            }
        }
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

        menu.addItem(makeItem("Add or view protected websites…", action: #selector(manage)))
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
