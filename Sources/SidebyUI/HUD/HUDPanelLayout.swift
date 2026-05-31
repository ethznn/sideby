import CoreGraphics

public enum HUDPanelLayout {
    public static func contentSize(
        fittingSize: CGSize,
        text: String,
        visualScale: Double
    ) -> CGSize {
        let scale = max(CGFloat(visualScale), 1)
        let fallbackWidth = CGFloat(text.count * 10) * scale + 44 * scale
        let measuredWidth = fittingSize.width > 1 ? fittingSize.width : fallbackWidth
        let measuredHeight = fittingSize.height > 1 ? fittingSize.height : 44 * scale
        let minimumWidth = 132 * scale
        let maximumWidth = 420 * scale
        let minimumHeight = 44 * scale
        let maximumHeight = 72 * scale

        return CGSize(
            width: min(max(measuredWidth, minimumWidth), maximumWidth),
            height: min(max(measuredHeight, minimumHeight), maximumHeight)
        )
    }

    public static func centeredOrigin(panelSize: CGSize, screenFrame: CGRect) -> CGPoint {
        CGPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.midY - panelSize.height / 2
        )
    }
}
