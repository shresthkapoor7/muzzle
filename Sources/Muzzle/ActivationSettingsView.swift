import SwiftUI
import AppKit

struct ActivationSettingsView: View {
    @ObservedObject var preferences = ActivationPreferences.shared
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsPanelHeader(title: "Shortcuts", isExpanded: expanded,
                                toggle: { expanded.toggle() }) { EmptyView() }
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Keyboard shortcut").font(.headline)
                    HStack {
                        ShortcutRecorder(shortcut: $preferences.settings.shortcut)
                            .frame(height: 28)
                        Button("Clear") { preferences.settings.shortcut = nil }
                            .disabled(preferences.settings.shortcut == nil)
                    }
                    Text("Click to record, then press a key with Control, Option, or Command. Escape cancels. Works while Muzzle is running.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = preferences.registrationError {
                        Text(error).font(.system(size: 12)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    ActivationSessionFields(session: $preferences.settings.keyboardSession)
                    Divider().padding(.vertical, 4)
                    Toggle("Enable Control-click on the menu-bar icon", isOn: $preferences.settings.controlClickEnabled)
                    Text("Hold Control and click Muzzle to start the session below using your saved websites.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if preferences.settings.controlClickEnabled {
                        ActivationSessionFields(session: $preferences.settings.controlClickSession)
                    }
                    Text("Starts protection for your saved websites. An active session stays unchanged. Indefinite sessions require a Poke API key.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ActivationSessionFields: View {
    @Binding var session: ActivationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Starts", selection: $session.timed) {
                Text("Timed").tag(true)
                Text("Indefinite").tag(false)
            }.pickerStyle(.segmented)
            if session.timed {
                HStack {
                    TextField("30", text: $session.minutes)
                        .textFieldStyle(.roundedBorder).frame(width: 70)
                        .accessibilityLabel("Shortcut duration in minutes")
                    Text("minutes")
                }
                if session.duration == nil {
                    Text("Enter a valid positive whole number of minutes.")
                        .font(.system(size: 12)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Picker("Bypasses allowed", selection: $session.bypasses) {
                ForEach(0...3, id: \.self) { Text("\($0)").tag($0) }
            }
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: ActivationShortcut?
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(RecorderButton.record)
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.savedTitle = shortcut?.label ?? "Record shortcut…"
        if !button.recording { button.title = button.savedTitle }
        button.onRecord = { shortcut = $0 }
        button.setAccessibilityLabel("Record activation shortcut")
    }
}

private final class RecorderButton: NSButton {
    var onRecord: ((ActivationShortcut) -> Void)?
    var savedTitle = "Record shortcut…"
    var recording = false { didSet { ActivationPreferences.shared.isRecording = recording } }
    override var acceptsFirstResponder: Bool { true }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
            if recording { finish() }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(recordingWindowEnded),
                                                   name: name, object: window)
        }
    }

    @objc private func recordingWindowEnded(_ notification: Notification) {
        if recording { finish() }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc func record() {
        recording = true
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish(); return }
        guard let shortcut = ActivationShortcut(event: event) else {
            title = "Include ⌃, ⌥, or ⌘…"
            return
        }
        recording = false
        onRecord?(shortcut)
        title = shortcut.label
    }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
    private func finish() { recording = false; title = savedTitle }
}
