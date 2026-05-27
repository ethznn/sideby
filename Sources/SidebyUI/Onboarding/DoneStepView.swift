import SidebyCore
import SwiftUI

public struct DoneStepView: View {
    private let language: AppLanguage

    public init(language: AppLanguage = .english) {
        self.language = language
    }

    public var body: some View {
        let strings = SBSStrings(language: language)

        VStack(alignment: .leading, spacing: 16) {
            Text(strings.onboardingDoneTitle)
                .font(.title2.weight(.semibold))

            Text(strings.onboardingDoneBody)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            MenuBarPreviewIllustration()
                .frame(width: 280, height: 96)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
    }
}

private struct MenuBarPreviewIllustration: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Finder")
                    .font(.caption.weight(.semibold))
                Text("File")
                    .font(.caption)
                Text("Edit")
                    .font(.caption)
                Spacer()
                highlightedStatusIcon
                Image(systemName: "wifi")
                    .font(.caption)
                Image(systemName: "battery.100")
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Tokens.accent.opacity(0.70))

            LinearGradient(
                colors: [
                    Tokens.accent.opacity(0.64),
                    Tokens.accent.opacity(0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.corner.panel, style: .continuous))
    }

    private var highlightedStatusIcon: some View {
        statusIcon
            .frame(width: 22, height: 18)
            .padding(.horizontal, 3)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
                    .frame(width: 26, height: 20)
            }
    }

    private var statusIcon: some View {
        ZStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 19, height: 17)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .stroke(Color.white, lineWidth: 1.1)
                .frame(width: 7.0, height: 5.3)
                .offset(x: -2.0, y: -0.8)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.white)
                .frame(width: 7.0, height: 5.3)
                .offset(x: 2.0, y: 1.9)
        }
        .frame(width: 22, height: 18)
    }
}
