import AppKit
import SwiftUI

struct BypassWarningState {
    private var warnedEndDate: Date?

    mutating func shouldWarn(start: Date?, end: Date?, now: Date) -> Bool {
        guard let start, let end else {
            warnedEndDate = nil
            return false
        }
        let remaining = end.timeIntervalSince(now)
        guard end != warnedEndDate, end.timeIntervalSince(start) > 120,
              remaining > 0, remaining <= 120 else { return false }
        warnedEndDate = end
        return true
    }
}

private final class BypassWarningPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class BypassWarningController {
    static let soundPreference = "MuzzleBypassWarningSound"
    private let blocker: BlockerController
    private var state = BypassWarningState()
    private var timer: Timer?
    private var panel: NSPanel?
    private var dismissAt: Date?
    private var displayedEndDate: Date?

    init(blocker: BlockerController) {
        self.blocker = blocker
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func update() {
        let now = Date()
        let end = blocker.bypassEndDate
        if panel != nil, end != displayedEndDate || end.map({ $0 <= now }) == true || dismissAt.map({ $0 <= now }) == true {
            dismiss()
        }
        guard state.shouldWarn(start: blocker.bypassSessionStartDate, end: end, now: now), let end else { return }
        show(end: end, now: now)
    }

    private func show(end: Date, now: Date) {
        let panel = BypassWarningPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 112),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: BypassWarningView(
            title: end.timeIntervalSince(now) >= 119 ? "2 minutes left in your bypass" : "Your bypass ends soon",
            onDismiss: { [weak self] in self?.dismiss() }
        ))
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 356, y: frame.maxY - 128))
        }
        self.panel = panel
        displayedEndDate = end
        dismissAt = now.addingTimeInterval(12)
        panel.orderFrontRegardless()
        if UserDefaults.standard.bool(forKey: Self.soundPreference) {
            NSSound(named: "Glass")?.play()
        }
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        dismissAt = nil
        displayedEndDate = nil
    }
}

private struct BypassWarningView: View {
    let title: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 22))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Muzzle").font(.caption).foregroundStyle(.secondary)
                Text(title).font(.system(size: 13, weight: .semibold))
                Text("Protected websites will block again.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss bypass reminder")
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
