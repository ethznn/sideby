import AppKit
import XCTest
@testable import SidebyApp

final class HeldWorkspaceWheelTests: XCTestCase {
    func testWholePanelStaysOnPointerDisplayIncludingFooter() {
        for screen in [NSRect(x: -1920, y: -300, width: 1920, height: 1055),
                       NSRect(x: 320, y: 1440, width: 800, height: 560),
                       NSRect(x: 0, y: 0, width: 340, height: 380)] {
            let size = HeldWorkspaceWheelLayout.size(in: screen)
            for x in [screen.minX, screen.midX, screen.maxX] {
                for y in [screen.minY, screen.midY, screen.maxY] {
                    let rect = NSRect(origin: HeldWorkspaceWheelLayout.origin(size: size, pointer: NSPoint(x: x, y: y), visibleFrame: screen), size: size)
                    XCTAssertTrue(screen.contains(rect), "Ring, header and actions must all fit")
                }
            }
        }
        XCTAssertFalse(HeldWorkspaceWheelLayout.fits(in: NSRect(x: 0, y: 0, width: 340, height: 380)))
    }

    func testPointerStartsAtRingCenterAwayFromScreenEdges() {
        let screen = NSRect(x: -1800, y: 0, width: 1800, height: 1100)
        let pointer = NSPoint(x: screen.midX, y: screen.midY)
        let size = HeldWorkspaceWheelLayout.size(in: screen)
        let origin = HeldWorkspaceWheelLayout.origin(size: size, pointer: pointer, visibleFrame: screen)
        XCTAssertEqual(origin.x + size.width / 2, pointer.x)
        XCTAssertEqual(origin.y + size.height - HeldWorkspaceWheelLayout.ringTop - (size.width - 32) / 2, pointer.y)
    }

    func testEveryDestinationAndItsToolsBelongToOneSector() {
        for count in 1...8 {
            for index in 0..<count {
                let point = HeldWorkspaceWheelLayout.labelPoint(index: index, count: count)
                XCTAssertEqual(HeldWorkspaceWheelLayout.sector(at: point, count: count), index)
                for dx in [-31.0, -3, 3, 31] {
                    for dy in [19.0, 45] {
                        XCTAssertEqual(HeldWorkspaceWheelLayout.sector(at: CGPoint(x: point.x + dx, y: point.y + dy), count: count), index,
                                       "Tools must not cross another sector, count=\(count), index=\(index)")
                    }
                }
            }
            XCTAssertNil(HeldWorkspaceWheelLayout.sector(at: CGPoint(x: 220, y: 220), count: count))
            XCTAssertNil(HeldWorkspaceWheelLayout.sector(at: .zero, count: count))
        }
    }

    func testPagingKeepsEveryConnectionExactlyOnceInManualOrder() {
        for count in [0, 1, 2, 3, 8, 9, 17, 40] {
            let indexes = (0..<HeldWorkspaceWheelLayout.pageCount(count)).flatMap { HeldWorkspaceWheelLayout.pageRange($0, count: count) }
            XCTAssertEqual(indexes, Array(0..<count))
            XCTAssertEqual(HeldWorkspaceWheelLayout.pageRange(99, count: count), HeldWorkspaceWheelLayout.pageRange(HeldWorkspaceWheelLayout.pageCount(count) - 1, count: count))
        }
    }

    func testSectorGapsHaveTheSamePointWidthAtInnerAndOuterEdges() {
        XCTAssertEqual(HeldWorkspaceWheelLayout.innerRadius - HeldWorkspaceWheelLayout.centerRadius, HeldWorkspaceWheelLayout.gap)
        for count in 2...8 {
            let step = 2 * Double.pi / Double(count)
            for index in 0..<count {
                let boundary = -Double.pi / 2 - step / 2 + Double(index) * step
                let direction = CGPoint(x: cos(boundary), y: sin(boundary))
                let normal = CGPoint(x: -direction.y, y: direction.x)
                for radius in [110.0, 155, 205] {
                    for offset in [-4.9, 0, 4.9] {
                        let point = CGPoint(x: 220 + radius * direction.x + offset * normal.x,
                                            y: 220 + radius * direction.y + offset * normal.y)
                        XCTAssertNil(HeldWorkspaceWheelLayout.sector(at: point, count: count))
                        for sector in 0..<count {
                            XCTAssertFalse(ConnectionSector(index: sector, count: count).path(in: CGRect(x: 0, y: 0, width: 440, height: 440)).contains(point))
                        }
                    }
                    let point = CGPoint(x: 220 + radius * direction.x + 5.1 * normal.x,
                                        y: 220 + radius * direction.y + 5.1 * normal.y)
                    XCTAssertEqual(HeldWorkspaceWheelLayout.sector(at: point, count: count), index)
                    XCTAssertTrue(ConnectionSector(index: index, count: count).path(in: CGRect(x: 0, y: 0, width: 440, height: 440)).contains(point))
                }
            }
        }
    }
}
