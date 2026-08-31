import AppKit
import SwiftUI

@MainActor
final class ManagementWindowController: NSWindowController {
    init(
        blocker: BlockerController,
        isDebugMode: Bool,
        onProtectionStarted: @escaping () -> Void,
        onRetrySystemUpdate: @escaping () -> Void
    ) {
        let rootView = ManagementView(
            blocker: blocker,
            isDebugMode: isDebugMode,
            onProtectionStarted: onProtectionStarted,
            onRetrySystemUpdate: onRetrySystemUpdate
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Muzzle"
        window.setContentSize(NSSize(width: 560, height: 620))
        window.minSize = NSSize(width: 500, height: 540)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("Muzzle windows are created in code.")
    }
}

private struct ManagementView: View {
    @ObservedObject var blocker: BlockerController
    let isDebugMode: Bool
    let onProtectionStarted: () -> Void
    let onRetrySystemUpdate: () -> Void
    @State private var domainInput = ""
    @State private var blockMode = BlockMode.timed
    @State private var timedMinutesInput = "30"
    @State private var allowedBypasses = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            setupPanel
            blockedList
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 460)
        .alert(
            "Couldn’t update website blocking",
            isPresented: Binding(
                get: { blocker.lastErrorMessage != nil },
                set: { if !$0 { blocker.clearError() } }
            )
        ) {
            if blocker.canRetrySystemUpdate {
                Button("Try Again") { onRetrySystemUpdate() }
            }
            Button("OK", role: .cancel) { blocker.clearError() }
        } message: {
            Text(blocker.lastErrorMessage ?? "Unknown error")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Muzzle", systemImage: "shield.lefthalf.filled")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.primary)
            Text(blocker.statusMessage)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            if isDebugMode {
                Text("Debug mode is an isolated UI sandbox. Poke and system website blocking are disabled.")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(blocker.blockedDomains.isEmpty ? "Start protection" : "Add a protected website")
                .font(.system(size: 15, weight: .semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow(alignment: .center) {
                    formLabel("Website")
                    HStack(spacing: 8) {
                        TextField("example.com", text: $domainInput)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Website domain")
                            .onSubmit(addDomain)
                        Button("Block", action: addDomain)
                            .buttonStyle(.borderedProminent)
                            .disabled(isBlockDisabled)
                            .accessibilityHint("Adds this website to the hosts-file block list")
                    }
                }

                if blocker.blockedDomains.isEmpty {
                    GridRow(alignment: .center) {
                        formLabel("Session")
                        HStack(spacing: 10) {
                            Picker("Block duration", selection: $blockMode) {
                                ForEach(BlockMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 250)

                            if blockMode == .timed {
                                TextField("30", text: $timedMinutesInput)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 56)
                                    .multilineTextAlignment(.trailing)
                                    .accessibilityLabel("Block duration in minutes")
                                    .help("Enter a positive whole number of minutes")
                                Text("min")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    GridRow(alignment: .center) {
                        formLabel("Bypasses")
                        HStack(spacing: 10) {
                            Picker("Bypasses allowed", selection: $allowedBypasses) {
                                ForEach(0...3, id: \.self) { count in
                                    Text("\(count)").tag(count)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 152)
                            Text("allowed")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if blocker.blockedDomains.isEmpty {
                Text(
                    isDebugMode
                        ? "Debug mode is in memory only; it does not change website blocking on this Mac."
                        : blockMode == .timed
                        ? "Timed sessions do not notify Poke. Bypasses temporarily restore access."
                        : "Muzzle asks for an optional Poke note after locking. Bypasses temporarily restore access."
                )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Text("Use a domain such as youtube.com; its www version is included too.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 80, alignment: .trailing)
    }

    private var blockedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Protected websites")
                .font(.system(size: 13, weight: .semibold))

            if blocker.blockedDomains.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Nothing blocked yet")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Add a domain above to block it across this Mac.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 170)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                List {
                    ForEach(blocker.blockedDomains, id: \.self) { domain in
                        HStack {
                            Text(domain)
                                .font(.system(size: 14))
                            Spacer()
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Protected until the session unlock key is used")
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 170)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if blocker.isApplying {
                ProgressView()
                    .controlSize(.small)
                Text("Updating macOS hosts file…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if blocker.isBypassActive {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Text("Bypass is active. New websites will block when it ends.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if blocker.isTimedSession {
                Image(systemName: "clock.fill")
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Text("This timed session ends automatically.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Text("The session key is required to end protection or remove sites.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func addDomain() {
        let wasInactive = blocker.blockedDomains.isEmpty
        guard !wasInactive || blockMode == .untilEnded || timedMinutes != nil else { return }
        blocker.add(
            domainInput,
            timedDurationMinutes: wasInactive && blockMode == .timed ? timedMinutes : nil,
            allowedBypasses: wasInactive ? allowedBypasses : 1
        )
        if wasInactive, !blocker.blockedDomains.isEmpty {
            if blockMode == .untilEnded {
                onProtectionStarted()
            }
        }
        domainInput = ""
    }

    private var timedMinutes: Int? {
        let value = timedMinutesInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = Int(value), DurationValidator.seconds(for: minutes) != nil else { return nil }
        return minutes
    }

    private var isBlockDisabled: Bool {
        domainInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || blocker.isApplying
            || (blocker.blockedDomains.isEmpty && blockMode == .timed && timedMinutes == nil)
    }
}

private enum BlockMode: String, CaseIterable, Identifiable {
    case timed
    case untilEnded

    var id: Self { self }

    var title: String {
        switch self {
        case .timed: "For a set time"
        case .untilEnded: "Until I end it"
        }
    }
}
