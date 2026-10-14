import AppKit
import XCTest
@testable import SidebyApp

final class PopoverScreenLayoutTests: XCTestCase {
    func testFitsTheEntireWindowIncludingChromeOnOffsetAndSmallDisplays() {
        for visible in [NSRect(x: -1920, y: -300, width: 1920, height: 1080),
                        NSRect(x: 100, y: 900, width: 300, height: 240)] {
            let bounds = PopoverScreenLayout.bounds(in: visible)
            let available = PopoverScreenLayout.contentSize(window: NSSize(width: 316, height: 426),
                content: NSSize(width: 290, height: 400), bounds: bounds.size)
            let size = NSSize(width: min(290, available.width) + 26, height: min(400, available.height) + 26)
            for point in [NSPoint(x: visible.minX - 100, y: visible.minY - 100),
                          NSPoint(x: visible.maxX + 100, y: visible.maxY + 100)] {
                let frame = NSRect(origin: point, size: size)
                let corrected = NSRect(origin: PopoverScreenLayout.origin(for: frame, in: bounds), size: size)
                XCTAssertTrue(bounds.contains(corrected))
                XCTAssertEqual(PopoverScreenLayout.origin(for: corrected, in: bounds), corrected.origin,
                               "A settled popover must not keep moving")
            }
        }
    }
}
