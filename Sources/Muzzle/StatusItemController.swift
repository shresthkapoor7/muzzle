import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let blocker: BlockerController
    private let onManage: () -> Void
    private let onEndSession: () -> Void
    private let onQuit: () -> Void
    private let statusItem: NSStatusItem
    private var blockerObservation: AnyCancellable?

    init(
        blocker: BlockerController,
        onManage: @escaping () -> Void,
        onEndSession: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.blocker = blocker
        self.onManage = onManage
        self.onEndSession = onEndSession
        self.onQuit = onQuit
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
        button.image = MuzzleStatusIcon.make(isActive: isBlocking)
        button.image?.accessibilityDescription = isBlocking ? "Muzzle is active" : "Muzzle is inactive"
        button.image?.isTemplate = true
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = isBlocking ? "Muzzle: active" : "Muzzle: inactive"
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let title = NSMenuItem(title: "Muzzle", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let status = NSMenuItem(title: blocker.statusMessage, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let manageTitle = blocker.blockedDomains.isEmpty ? "Start blocking…" : "Manage protected websites…"
        menu.addItem(makeItem(manageTitle, action: #selector(manage)))
        menu.addItem(.separator())
        if blocker.blockedDomains.isEmpty {
            menu.addItem(makeItem("Quit Muzzle", action: #selector(quit)))
        } else {
            menu.addItem(makeItem("End protection with key…", action: #selector(endSession)))
        }

        statusItem.menu = menu
    }

    private func makeItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func manage() { onManage() }
    @objc private func endSession() { onEndSession() }
    @objc private func quit() { onQuit() }
}

private enum MuzzleStatusIcon {
    static func make(isActive: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let mask = maskPath()
            NSColor.black.setStroke()
            NSColor.black.setFill()

            if isActive {
                mask.fill()
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .clear
                grillePaths().forEach { grille in
                    grille.lineWidth = 1.2
                    grille.stroke()
                }
                NSGraphicsContext.restoreGraphicsState()
            } else {
                mask.lineWidth = 1.65
                mask.stroke()
                grillePaths().forEach { grille in
                    grille.lineWidth = 1.2
                    grille.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func maskPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 4.1, y: 15.2))
        path.line(to: NSPoint(x: 13.9, y: 15.2))
        path.line(to: NSPoint(x: 16.4, y: 11.3))
        path.line(to: NSPoint(x: 14.5, y: 2.5))
        path.line(to: NSPoint(x: 3.5, y: 2.5))
        path.line(to: NSPoint(x: 1.6, y: 11.3))
        path.close()
        return path
    }

    private static func grillePaths() -> [NSBezierPath] {
        [6.0, 9.0, 12.0].map { y in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 5.1, y: y))
            path.line(to: NSPoint(x: 12.9, y: y))
            return path
        }
    }
}
