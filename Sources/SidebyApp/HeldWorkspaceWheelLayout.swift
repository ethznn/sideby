import AppKit

enum HeldSwitcherPresentation { case wheel, table, editor }

/// Chosen once when opening the menu, independently of the hovered connection.
struct HeldWorkspaceWheelGeometry: Equatable {
    var displayCount = 2
    var expansion: CGFloat { CGFloat(max(0, displayCount - 2)) * 20 }
    var centerRadius: CGFloat { 84 + expansion }
    var innerRadius: CGFloat { centerRadius + HeldWorkspaceWheelLayout.gap }
    var outerRadius: CGFloat { 218 + expansion }
    var diameter: CGFloat { 440 + expansion * 2 }
    var midpoint: CGFloat { diameter / 2 }
    var labelRadius: CGFloat { 158 + expansion }
    var previewWidth: CGFloat { displayCount > 2 ? 160 : 132 }
}

/// One stable ring per page. Adding a connection never resizes the panel.
enum HeldWorkspaceWheelLayout {
    static let pageSize = 8
    static let gap: CGFloat = 10
    static let innerRadius: CGFloat = centerRadius + gap
    static let outerRadius: CGFloat = 218
    static let centerRadius: CGFloat = 84
    static let diameter: CGFloat = 440
    static let ringTop: CGFloat = 8
    static let chromeHeight: CGFloat = 128

    static func size(in visibleFrame: NSRect, geometry: HeldWorkspaceWheelGeometry = .init()) -> NSSize {
        let ring = max(1, min(geometry.diameter, visibleFrame.width - 64, visibleFrame.height - chromeHeight - 32))
        return NSSize(width: ring + 32, height: ring + chromeHeight)
    }

    static func fits(in visibleFrame: NSRect, geometry: HeldWorkspaceWheelGeometry = .init()) -> Bool {
        (size(in: visibleFrame, geometry: geometry).width - 32) / geometry.diameter >= 320 / 440
    }

    static func origin(size: NSSize, pointer: NSPoint, visibleFrame: NSRect) -> NSPoint {
        let bounds = visibleFrame.insetBy(dx: 16, dy: 16)
        let ring = size.width - 32
        return NSPoint(x: max(bounds.minX, min(pointer.x - size.width / 2, bounds.maxX - size.width)),
            y: max(bounds.minY, min(pointer.y - (size.height - ringTop - ring / 2), bounds.maxY - size.height)))
    }

    static func pageCount(_ count: Int) -> Int { max(1, (count + pageSize - 1) / pageSize) }
    static func pageRange(_ page: Int, count: Int) -> Range<Int> {
        let start = max(0, min(page, pageCount(count) - 1)) * pageSize
        return start..<min(count, start + pageSize)
    }

    /// SwiftUI's top-left coordinate system. The center is a neutral save target;
    /// neither hover nor releasing the opening shortcut performs an action.
    static func sector(at point: CGPoint, count: Int, geometry: HeldWorkspaceWheelGeometry = .init()) -> Int? {
        guard count > 0 else { return nil }
        let dx = point.x - geometry.midpoint, dy = point.y - geometry.midpoint
        let radius = hypot(dx, dy)
        guard radius >= geometry.innerRadius, radius <= geometry.outerRadius else { return nil }
        let step = 360.0 / Double(count)
        let start = -90 - step / 2
        let angle = (atan2(dy, dx) * 180 / .pi - start + 720).truncatingRemainder(dividingBy: 360)
        let local = angle.truncatingRemainder(dividingBy: step)
        let edgeDistance = radius * sin(min(local, step - local) * .pi / 180)
        guard count == 1 || edgeDistance >= gap / 2 else { return nil }
        return min(count - 1, Int(angle / step))
    }

    static func labelPoint(index: Int, count: Int, geometry: HeldWorkspaceWheelGeometry = .init()) -> CGPoint {
        let angle = (-90 + Double(index) * 360 / Double(max(1, count))) * .pi / 180
        return CGPoint(x: geometry.midpoint + geometry.labelRadius * cos(angle),
                       y: geometry.midpoint + geometry.labelRadius * sin(angle))
    }

    static func nameFontSize(count: Int) -> CGFloat { count <= 4 ? 18 : 15 }
    static func toolsOffset(count: Int) -> CGFloat { count <= 4 ? 36 : 32 }

    /// Use the actual horizontal room in each curved sector. Top/bottom sectors
    /// can hold wider names than the narrow radial band at the sides.
    static func labelFrame(index: Int, count: Int, geometry: HeldWorkspaceWheelGeometry = .init()) -> CGRect {
        let point = labelPoint(index: index, count: count, geometry: geometry)
        let height: CGFloat = count <= 4 ? 62 : 56
        let centerY = point.y - (count <= 4 ? 11 : 12)
        let maximum: CGFloat = count <= 4 ? 200 : 128
        for width in stride(from: maximum, through: 64, by: -2) {
            let rect = CGRect(x: point.x - width / 2, y: centerY - height / 2, width: width, height: height)
            let padded = rect.insetBy(dx: -2, dy: -2)
            let xs = [padded.minX, padded.midX, padded.maxX]
            let ys = [padded.minY, padded.midY, padded.maxY]
            if xs.allSatisfy({ x in ys.allSatisfy { y in sector(at: CGPoint(x: x, y: y), count: count, geometry: geometry) == index } }) {
                return rect
            }
        }
        return CGRect(x: point.x - 32, y: centerY - height / 2, width: 64, height: height)
    }
}
