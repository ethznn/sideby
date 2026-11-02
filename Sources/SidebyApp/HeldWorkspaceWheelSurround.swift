import AppKit
import QuartzCore
import SwiftUI

/// Decoration only: cached shadow geometry and one short opacity animation.
/// The wheel's layout, hit regions and immediate dismissal never animate.
struct HeldWorkspaceWheelSurround: NSViewRepresentable {
    let geometry: HeldWorkspaceWheelGeometry
    let count: Int
    let isActive: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> SurroundView { SurroundView() }
    func updateNSView(_ view: SurroundView, context: Context) {
        view.configure(geometry: geometry, count: count, isActive: isActive, reduceMotion: reduceMotion)
    }

    /// Start after ordering the window onscreen, not during hidden host layout.
    static func reveal(in root: NSView?) {
        guard let root else { return }
        if let view = root as? SurroundView { view.revealIfNeeded(isVisible: view.window?.isVisible == true) }
        for child in root.subviews { reveal(in: child) }
    }

    final class SurroundView: NSView {
        private let elevation = CAShapeLayer()
        private let keyline = CAShapeLayer()
        private let outline = CAShapeLayer()
        let highlight = CAShapeLayer()
        private var geometry = HeldWorkspaceWheelGeometry()
        private var count = 0
        private var active = false
        private var reduceMotion = false
        private var hasRevealed = false
        private var drawnSize = CGSize.zero
        private var geometryDirty = true
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            setAccessibilityElement(false)
            layer?.masksToBounds = false
            elevation.shadowRadius = 6
            elevation.shadowOffset = CGSize(width: 0, height: -3)
            layer?.addSublayer(elevation)
            for shape in [keyline, outline, highlight] {
                shape.fillColor = nil
                layer?.addSublayer(shape)
            }
            keyline.lineWidth = 3
            outline.lineWidth = 1.5
            highlight.lineWidth = 2.25
            highlight.opacity = 0
            updateColors()
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func configure(geometry: HeldWorkspaceWheelGeometry, count: Int, isActive: Bool, reduceMotion: Bool) {
            if self.geometry != geometry || self.count != count {
                self.geometry = geometry; self.count = count; geometryDirty = true
            }
            active = isActive
            self.reduceMotion = reduceMotion
            if !isActive {
                hasRevealed = false
                highlight.removeAllAnimations()
            }
            if reduceMotion { highlight.removeAllAnimations() }
            needsLayout = geometryDirty || drawnSize != bounds.size
            revealIfNeeded(isVisible: window?.isVisible == true)
        }

        func revealIfNeeded(isVisible: Bool) {
            guard active, isVisible, !hasRevealed else { return }
            hasRevealed = true
            guard !reduceMotion else { return }
            let cue = CAKeyframeAnimation(keyPath: "opacity")
            cue.values = [1, 1, 0]
            cue.keyTimes = [0, NSNumber(value: 0.4 / 0.7), 1]
            cue.duration = 0.7
            cue.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
            highlight.add(cue, forKey: "appearance")
        }

        override func layout() {
            super.layout()
            guard bounds.width > 0, bounds.height > 0, geometryDirty || drawnSize != bounds.size else { return }
            geometryDirty = false; drawnSize = bounds.size
            let scale = min(bounds.width, bounds.height) / geometry.diameter
            let origin = CGPoint(x: bounds.midX - geometry.midpoint * scale, y: bounds.midY - geometry.midpoint * scale)
            let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: origin.x, ty: origin.y)
            let silhouette = CGMutablePath()
            for index in 0..<max(1, count) {
                silhouette.addPath(HeldWorkspaceWheelLayout.sectorPath(index: index, count: max(1, count), geometry: geometry), transform: transform)
            }
            let center = CGRect(x: geometry.midpoint - geometry.centerRadius, y: geometry.midpoint - geometry.centerRadius,
                width: geometry.centerRadius * 2, height: geometry.centerRadius * 2)
            silhouette.addEllipse(in: center, transform: transform)
            let radius = geometry.outerRadius * scale + 0.5
            let rim = CGPath(ellipseIn: CGRect(x: bounds.midX - radius, y: bounds.midY - radius,
                width: radius * 2, height: radius * 2), transform: nil)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            elevation.frame = bounds
            elevation.path = silhouette
            elevation.shadowPath = silhouette
            for shape in [keyline, outline, highlight] { shape.frame = bounds; shape.path = rim }
            CATransaction.commit()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateColors()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { highlight.removeAllAnimations(); hasRevealed = false }
        }

        private func updateColors() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                elevation.shadowColor = NSColor.black.cgColor
                elevation.shadowOpacity = dark ? 0.32 : 0.18
                elevation.fillColor = NSColor(HeldWorkspaceWheelStyle.chrome).cgColor
                // A pale outer keyline remains visible on a dark desktop even
                // when the app itself is using a light appearance.
                keyline.strokeColor = NSColor.white.withAlphaComponent(dark ? 0.16 : 0.7).cgColor
                outline.strokeColor = NSColor(HeldWorkspaceWheelStyle.outline).cgColor
                highlight.strokeColor = NSColor(HeldWorkspaceWheelStyle.outlineHighlight).cgColor
                CATransaction.commit()
            }
        }
    }
}
