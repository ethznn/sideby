import SwiftUI

public struct Kbd: View {
    public let text: String
    public var width: CGFloat?

    public init(text: String, width: CGFloat? = nil) {
        self.text = text
        self.width = width
    }

    public var body: some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: width, height: 22)
            .padding(.horizontal, width == nil ? 7 : 0)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.corner.kbd, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.corner.kbd, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
    }
}
