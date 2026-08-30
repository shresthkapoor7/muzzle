import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let blocker: BlockerController
    private let onManage: () -> Void
    private let onEndSession: () -> Void
    private let onBypass: () -> Void
    private let onRetrySystemUpdate: () -> Void
    private let onQuit: () -> Void
    private let statusItem: NSStatusItem
    private var blockerObservation: AnyCancellable?

    init(
        blocker: BlockerController,
        onManage: @escaping () -> Void,
        onEndSession: @escaping () -> Void,
        onBypass: @escaping () -> Void,
        onRetrySystemUpdate: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.blocker = blocker
        self.onManage = onManage
        self.onEndSession = onEndSession
        self.onBypass = onBypass
        self.onRetrySystemUpdate = onRetrySystemUpdate
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

        let isBlocking = blocker.isProtectionEnforced
        let isBypassCountdown = blocker.isBypassActive && blocker.bypassSessionStartDate != nil
        button.image = MuzzleIcon.statusImage(
            isActive: isBlocking || isBypassCountdown,
            fillFraction: isBypassCountdown ? blocker.bypassProgress : 1
        )
        button.image?.accessibilityDescription = isBlocking
            ? "Muzzle is active"
            : blocker.isBypassActive ? "Muzzle bypass is active" : "Muzzle is inactive"
        button.image?.isTemplate = true
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = isBlocking ? "Muzzle: active" : blocker.isBypassActive ? "Muzzle: bypass active" : "Muzzle: inactive"
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
        if blocker.canRetrySystemUpdate {
            menu.addItem(.separator())
            menu.addItem(makeItem("Retry macOS permission…", action: #selector(retrySystemUpdate)))
        }
        if blocker.canQuit {
            menu.addItem(.separator())
            menu.addItem(makeItem("Quit Muzzle", action: #selector(quit)))
        } else {
            if blocker.canStartBypass {
                menu.addItem(.separator())
                menu.addItem(makeItem("Bypass… (\(blocker.remainingBypasses) left)", action: #selector(bypass)))
            }
            if !blocker.isTimedSession {
                menu.addItem(.separator())
                menu.addItem(makeItem("End protection with key…", action: #selector(endSession)))
            }
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
    @objc private func bypass() { onBypass() }
    @objc private func retrySystemUpdate() { onRetrySystemUpdate() }
    @objc private func quit() { onQuit() }
}
