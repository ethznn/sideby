import SwiftUI

public enum ChipTone {
    case ok
    case warn
    case info
    case neutral
}

public struct Chip: View {
    public let text: String
    public let tone: ChipTone
    public var showsDot: Bool

    public init(text: String, tone: ChipTone, showsDot: Bool = true) {
        self.text = text
        self.tone = tone
        self.showsDot = showsDot
    }

    public var body: some View {
        HStack(spacing: 5) {
            if showsDot {
                Circle()
                    .fill(foregroundColor)
                    .frame(width: 5, height: 5)
            }

            Text(text)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.corner.chip, style: .continuous))
    }

    private var foregroundColor: Color {
        switch tone {
        case .ok:
            Color(nsColor: .systemGreen)
        case .warn:
            Color(nsColor: .systemOrange)
        case .info:
            Tokens.accent
        case .neutral:
            Color.secondary
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .ok:
            Color(nsColor: .systemGreen).opacity(0.14)
        case .warn:
            Color(nsColor: .systemOrange).opacity(0.16)
        case .info:
            Tokens.accent.opacity(0.12)
        case .neutral:
            Color.secondary.opacity(0.10)
        }
    }
}
