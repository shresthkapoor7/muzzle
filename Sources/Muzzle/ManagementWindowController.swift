import AppKit
import SwiftUI

@MainActor
final class ManagementWindowController: NSWindowController {
    init(blocker: BlockerController, onProtectionStarted: @escaping (String?) -> Void) {
        let rootView = ManagementView(blocker: blocker, onProtectionStarted: onProtectionStarted)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Muzzle"
        window.setContentSize(NSSize(width: 520, height: 540))
        window.minSize = NSSize(width: 460, height: 460)
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
    let onProtectionStarted: (String?) -> Void
    @State private var domainInput = ""
    @State private var workingOnInput = ""
    @State private var blockMode = BlockMode.timed
    @State private var timedMinutesInput = "30"

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            addWebsiteForm
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
            Text("Protection is locked for this session.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var addWebsiteForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Block a website")
                .font(.system(size: 13, weight: .semibold))
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
            if blocker.blockedDomains.isEmpty {
                Picker("Block duration", selection: $blockMode) {
                    ForEach(BlockMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if blockMode == .timed {
                    HStack(spacing: 8) {
                        Text("Block for")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        TextField("30", text: $timedMinutesInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Block duration in minutes")
                            .help("Enter a positive whole number of minutes")
                        Text("minutes")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text("Timed blocks do not notify Poke.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    TextField("What are you working on? (optional)", text: $workingOnInput)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("What you are working on")
                }
            }
            Text("Use a domain only — for example, youtube.com. Its www version is blocked too.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
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
            timedDurationMinutes: wasInactive && blockMode == .timed ? timedMinutes : nil
        )
        if wasInactive, !blocker.blockedDomains.isEmpty {
            let workingOn = workingOnInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if blockMode == .untilEnded {
                onProtectionStarted(workingOn.isEmpty ? nil : workingOn)
            }
        }
        domainInput = ""
        workingOnInput = ""
    }

    private var timedMinutes: Int? {
        let value = timedMinutesInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = Int(value), minutes > 0 else { return nil }
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
