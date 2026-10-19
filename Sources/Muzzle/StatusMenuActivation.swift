import AppKit

/// Status-item clicks are forwarded by the system menu bar. Read the held modifier
/// when the native menu opens, rather than expecting a local mouse event/window.
@MainActor
final class StatusMenuActivation: NSObject, NSMenuDelegate {
    private let isEnabled: () -> Bool
    private let modifiers: () -> NSEvent.ModifierFlags
    private let activate: () -> Void
    private var activationPending = false

    init(isEnabled: @escaping () -> Bool,
         modifiers: @escaping () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags },
         activate: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.modifiers = modifiers
        self.activate = activate
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard isEnabled(), modifiers().contains(.control), !activationPending else { return }
        activationPending = true
        // Tracking begins after menuWillOpen returns. Cancel on the next main-loop
        // turn, then start protection so dialogs cannot nest inside menu tracking.
        DispatchQueue.main.async { [self] in
            menu.cancelTrackingWithoutAnimation()
            DispatchQueue.main.async { [self] in
                activationPending = false
                activate()
            }
        }
    }
}
