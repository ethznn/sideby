import AppKit

enum HeldSwitcherPresentation { case wheel, table, editor }

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

    static func size(in visibleFrame: NSRect) -> NSSize {
        let ring = max(1, min(diameter, visibleFrame.width - 64, visibleFrame.height - chromeHeight - 32))
        return NSSize(width: ring + 32, height: ring + chromeHeight)
    }

    static func fits(in visibleFrame: NSRect) -> Bool { size(in: visibleFrame).width >= 352 }

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
    static func sector(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let dx = point.x - 220, dy = point.y - 220
        let radius = hypot(dx, dy)
        guard radius >= innerRadius, radius <= outerRadius else { return nil }
        let step = 360.0 / Double(count)
        let start = -90 - step / 2
        let angle = (atan2(dy, dx) * 180 / .pi - start + 720).truncatingRemainder(dividingBy: 360)
        let local = angle.truncatingRemainder(dividingBy: step)
        let edgeDistance = radius * sin(min(local, step - local) * .pi / 180)
        guard count == 1 || edgeDistance >= gap / 2 else { return nil }
        return min(count - 1, Int(angle / step))
    }

    static func labelPoint(index: Int, count: Int) -> CGPoint {
        let angle = (-90 + Double(index) * 360 / Double(max(1, count))) * .pi / 180
        return CGPoint(x: 220 + 158 * cos(angle), y: 220 + 158 * sin(angle))
    }
}
