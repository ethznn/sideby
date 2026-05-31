import SwiftUI

public struct HUDView: View {
    public let state: HUDPresentationState

    public init(state: HUDPresentationState) {
        self.state = state
    }

    public var body: some View {
        ZStack {
            Text(state.text)
                .font(.system(size: fontSize, weight: fontWeight, design: .rounded))
                .foregroundStyle(state.backgroundOpacity > 0 ? .white : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(backgroundStyle)
                }
                .overlay {
                    if state.backgroundOpacity > 0 {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var fontSize: CGFloat {
        let baseSize: CGFloat = state.isCompact ? 12 : 13
        return baseSize * CGFloat(state.visualScale)
    }

    private var fontWeight: Font.Weight {
        state.visualScale > 1 ? .semibold : .regular
    }

    private var horizontalPadding: CGFloat {
        let basePadding: CGFloat = state.isCompact ? 10 : 14
        return basePadding * CGFloat(state.visualScale)
    }

    private var verticalPadding: CGFloat {
        let basePadding: CGFloat = state.isCompact ? 6 : 9
        return basePadding * CGFloat(state.visualScale)
    }

    private var cornerRadius: CGFloat {
        8 * CGFloat(state.visualScale)
    }

    private var backgroundStyle: AnyShapeStyle {
        if state.backgroundOpacity > 0 {
            AnyShapeStyle(.black.opacity(state.backgroundOpacity))
        } else {
            AnyShapeStyle(.regularMaterial)
        }
    }
}
