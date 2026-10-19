import SwiftUI

/// Shared disclosure header so every settings card has the same layout and hit area.
struct SettingsPanelHeader<Status: View>: View {
    let title: String
    let isExpanded: Bool
    let toggle: () -> Void
    @ViewBuilder var status: () -> Status

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 12)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                status()
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Show or hide \(title) controls")
    }
}
