import AppKit

/// Intercept Control-click before NSButton routes it to AppKit's contextual-menu handling.
@MainActor
final class StatusControlClickMonitor {
    nonisolated(unsafe) private var monitor: Any?

    init(button: NSStatusBarButton, isEnabled: @escaping () -> Bool, activate: @escaping () -> Void) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak button] event in
            let handled = MainActor.assumeIsolated {
                guard let button, let window = button.window,
                      Self.shouldHandle(event, windowNumber: window.windowNumber,
                                        buttonFrame: button.convert(button.bounds, to: nil), enabled: isEnabled()) else {
                    return false
                }
                // Consume the press so AppKit cannot also open a contextual menu.
                // Run activation after this event has finished dispatching.
                DispatchQueue.main.async { activate() }
                return true
            }
            return handled ? nil : event
        }
    }

    static func shouldHandle(_ event: NSEvent, windowNumber: Int, buttonFrame: NSRect, enabled: Bool) -> Bool {
        enabled && (event.type == .leftMouseDown || event.type == .rightMouseDown)
            && event.modifierFlags.contains(.control)
            && event.windowNumber == windowNumber
            && buttonFrame.contains(event.locationInWindow)
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
