import SidebyCore
import SwiftUI

public struct PermissionStepView: View {
    private let hasAccessibilityPermission: Bool
    private let hasSwitchingAccess: Bool
    private let language: AppLanguage

    public init(
        hasAccessibilityPermission: Bool,
        hasSwitchingAccess: Bool,
        language: AppLanguage = .english
    ) {
        self.hasAccessibilityPermission = hasAccessibilityPermission
        self.hasSwitchingAccess = hasSwitchingAccess
        self.language = language
    }

    public var body: some View {
        let strings = SBSStrings(language: language)

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(strings.onboardingPermissionTitle)
                    .font(.title2.weight(.semibold))

                Text(strings.onboardingPermissionSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                PermissionStatusCard(
                    symbolName: "lock.fill",
                    title: strings.accessibility,
                    subtitle: strings.permissionAccessibilitySubtitle,
                    chipText: hasAccessibilityPermission ? strings.grantedChip : strings.notGrantedChip,
                    chipTone: hasAccessibilityPermission ? .ok : .warn,
                    tint: Tokens.accent
                )

                PermissionStatusCard(
                    symbolName: "arrow.left.arrow.right",
                    title: strings.switchingAccess,
                    subtitle: strings.permissionSwitchingAccessSubtitle,
                    chipText: hasSwitchingAccess ? strings.grantedChip : strings.notGrantedChip,
                    chipTone: hasSwitchingAccess ? .ok : .warn,
                    tint: Color(nsColor: .systemGreen)
                )
            }
        }
    }
}

private struct PermissionStatusCard: View {
    let symbolName: String
    let title: String
    let subtitle: String
    let chipText: String
    let chipTone: ChipTone
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Chip(text: chipText, tone: chipTone)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.corner.panel, style: .continuous))
    }
}
