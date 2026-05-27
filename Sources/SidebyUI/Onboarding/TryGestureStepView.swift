import SidebyCore
import SwiftUI

public struct TryGestureStepView: View {
    private let detectedGestureCount: Int
    private let displayCount: Int
    private let language: AppLanguage
    private let skipTest: () -> Void

    public init(
        detectedGestureCount: Int,
        displayCount: Int,
        language: AppLanguage = .english,
        skipTest: @escaping () -> Void
    ) {
        self.detectedGestureCount = detectedGestureCount
        self.displayCount = displayCount
        self.language = language
        self.skipTest = skipTest
    }

    public var body: some View {
        let strings = SBSStrings(language: language)

        VStack(alignment: .leading, spacing: 15) {
            Text(strings.holdOptionShiftAndSwipe)
                .font(.title2.weight(.semibold))

            gestureCard
                .frame(maxWidth: .infinity, alignment: .center)

            Text(strings.keyboardShortcutsLater)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Chip(text: strings.displayCountChip(displayCount), tone: .neutral)
                Chip(text: strings.accessibilityOn, tone: .ok)
                Chip(text: detectedGestureCount >= 1 ? strings.detected : strings.listening, tone: detectedGestureCount >= 1 ? .ok : .info)
            }

            Button(strings.skipTest, action: skipTest)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Tokens.accent)
        }
    }

    private var gestureCard: some View {
        let strings = SBSStrings(language: language)

        return ZStack {
            RoundedRectangle(cornerRadius: Tokens.corner.panel, style: .continuous)
                .stroke(
                    detectedGestureCount >= 1 ? Color(nsColor: .systemGreen) : Color(nsColor: .separatorColor),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )

            VStack(spacing: 22) {
                HStack(spacing: 11) {
                    Kbd(text: "⌥", width: 34)
                    Kbd(text: "⇧", width: 34)
                    Text(strings.hold)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("+")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Tokens.accent)
                    Text(strings.swipeVerb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DottedTrail()
                    .frame(width: 235, height: 8)
            }
        }
        .frame(width: 360, height: 116)
    }
}

private struct DottedTrail: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<18, id: \.self) { index in
                Circle()
                    .fill(Tokens.accent.opacity(0.18 + Double(index) * 0.035))
                    .frame(width: 5, height: 5)
            }
        }
    }
}
