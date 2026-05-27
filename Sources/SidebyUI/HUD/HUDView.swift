import SwiftUI

public struct HUDView: View {
    public let state: HUDPresentationState

    public init(state: HUDPresentationState) {
        self.state = state
    }

    public var body: some View {
        Text(state.text)
            .font(state.isCompact ? .caption : .body)
            .padding(.horizontal, state.isCompact ? 10 : 14)
            .padding(.vertical, state.isCompact ? 6 : 9)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
