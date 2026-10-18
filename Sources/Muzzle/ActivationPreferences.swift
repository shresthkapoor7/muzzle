import AppKit
import Combine
import Carbon

struct ActivationSession: Codable, Equatable {
    var timed = true
    var minutes = "30"
    var bypasses = 1

    var duration: Int? {
        guard let value = Int(minutes), DurationValidator.seconds(for: value) != nil else { return nil }
        return value
    }
    var isValid: Bool { (!timed || duration != nil) && (0...3).contains(bypasses) }
}

struct ActivationShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option),
              let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = (flags.contains(.command) ? UInt32(cmdKey) : 0)
            | (flags.contains(.control) ? UInt32(controlKey) : 0)
            | (flags.contains(.option) ? UInt32(optionKey) : 0)
            | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
        label = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + characters.uppercased()
    }
}

@MainActor
final class ActivationPreferences: ObservableObject {
    static let shared = ActivationPreferences()
    struct Settings: Codable {
        var shortcut: ActivationShortcut?
        var keyboardSession = ActivationSession()
    }
    @Published var settings: Settings { didSet { persist(); onChange?() } }
    @Published var registrationError: String?
    var isRecording = false { didSet { onChange?() } }
    var onChange: (() -> Void)?
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, isDebugMode: Bool = DebugMode.isEnabled) {
        self.defaults = defaults
        key = isDebugMode ? "MuzzleDebugActivation" : "MuzzleActivation"
        settings = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }
}

/// Carbon registers a specific global combination without monitoring all keyboard input.
@MainActor
final class ActivationHotKey {
    // Accessed on the main actor; deinit only releases the Carbon resources.
    nonisolated(unsafe) private var hotKey: EventHotKeyRef?
    nonisolated(unsafe) private var handler: EventHandlerRef?
    private let onActivate: () -> Void

    init(onActivate: @escaping () -> Void) {
        self.onActivate = onActivate
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<ActivationHotKey>.fromOpaque(context).takeUnretainedValue().onActivate()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func update(_ shortcut: ActivationShortcut?) -> String? {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        guard let shortcut else { return nil }
        guard handler != nil else { return "Couldn’t register keyboard shortcuts on this Mac." }
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                        EventHotKeyID(signature: 0x4D5A4C45, id: 1),
                                        GetApplicationEventTarget(), 0, &hotKey)
        return result == noErr ? nil : "That shortcut is unavailable. Record a different combination."
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
