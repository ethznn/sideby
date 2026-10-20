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
                let toolsOffset = HeldWorkspaceWheelLayout.toolsOffset(count: count)
                for dx in [-31.0, -3, 3, 31] {
                    for dy in [toolsOffset - 13, toolsOffset + 13] {
                        XCTAssertEqual(HeldWorkspaceWheelLayout.sector(at: CGPoint(x: point.x + dx, y: point.y + dy), count: count), index,
                                       "Tools must not cross another sector, count=\(count), index=\(index)")
                    }
                }
            }
            XCTAssertNil(HeldWorkspaceWheelLayout.sector(at: CGPoint(x: 220, y: 220), count: count))
            XCTAssertNil(HeldWorkspaceWheelLayout.sector(at: .zero, count: count))
        }
    }

    func testEnlargedNameAndToolsStayInsideTheirOwnSectorWithoutOverlapping() {
        let ring = CGRect(x: 0, y: 0, width: 440, height: 440)
        for count in 1...8 {
            for index in 0..<count {
                let frame = HeldWorkspaceWheelLayout.labelFrame(index: index, count: count)
                let path = ConnectionSector(index: index, count: count).path(in: ring)
                for x in stride(from: frame.minX, through: frame.maxX, by: 2) {
                    for y in stride(from: frame.minY, through: frame.maxY, by: 2) {
                        XCTAssertTrue(path.contains(CGPoint(x: x, y: y)),
                            "Names must not cross the transparent gaps or adjacent sectors: \(count)/\(index)")
                    }
                }
                let point = HeldWorkspaceWheelLayout.labelPoint(index: index, count: count)
                let tools = CGRect(x: point.x - 31,
                    y: point.y + HeldWorkspaceWheelLayout.toolsOffset(count: count) - 13, width: 62, height: 26)
                XCTAssertFalse(frame.intersects(tools), "Two-line names/status must leave room for rename/delete")
            }
        }
    }

    func testPagingKeepsEveryConnectionExactlyOnceInManualOrder() {
        for count in [0, 1, 2, 3, 8, 9, 17, 40] {
            let indexes = (0..<HeldWorkspaceWheelLayout.pageCount(count)).flatMap { HeldWorkspaceWheelLayout.pageRange($0, count: count) }
            XCTAssertEqual(indexes, Array(0..<count))
            XCTAssertEqual(HeldWorkspaceWheelLayout.pageRange(99, count: count), HeldWorkspaceWheelLayout.pageRange(HeldWorkspaceWheelLayout.pageCount(count) - 1, count: count))
        }
    }

    func testExpandedCentersPreserveNamesControlsGapsAndScreenBounds() {
        for displays in [3, 4, 6, 12] {
            let geometry = HeldWorkspaceWheelGeometry(displayCount: displays)
            let bounds = CGRect(x: 0, y: 0, width: geometry.diameter, height: geometry.diameter)
            XCTAssertEqual(geometry.innerRadius - geometry.centerRadius, 10)
            XCTAssertEqual(geometry.outerRadius - geometry.innerRadius, 124, "Display rows must not consume the connection controls")
            for count in 1...8 {
                for index in 0..<count {
                    let path = ConnectionSector(index: index, count: count, geometry: geometry).path(in: bounds)
                    let label = HeldWorkspaceWheelLayout.labelFrame(index: index, count: count, geometry: geometry)
                    for x in stride(from: label.minX, through: label.maxX, by: 3) {
                        for y in stride(from: label.minY, through: label.maxY, by: 3) {
                            XCTAssertTrue(path.contains(CGPoint(x: x, y: y)))
                        }
                    }
                    let point = HeldWorkspaceWheelLayout.labelPoint(index: index, count: count, geometry: geometry)
                    for dx in [-31.0, 31] {
                        for dy in [-13.0, 13] {
                            let hit = CGPoint(x: point.x + dx,
                                y: point.y + HeldWorkspaceWheelLayout.toolsOffset(count: count) + dy)
                            XCTAssertEqual(HeldWorkspaceWheelLayout.sector(at: hit, count: count, geometry: geometry), index)
                            XCTAssertTrue(path.contains(hit))
                        }
                    }
                    let gap = CGPoint(x: geometry.midpoint, y: geometry.midpoint - geometry.centerRadius - 5)
                    XCTAssertNil(HeldWorkspaceWheelLayout.sector(at: gap, count: count, geometry: geometry))
                }
            }
            for screen in [NSRect(x: -1920, y: -300, width: 1920, height: 1055),
                           NSRect(x: 300, y: 1000, width: 800, height: 560)] {
                let size = HeldWorkspaceWheelLayout.size(in: screen, geometry: geometry)
                for pointer in [screen.origin, NSPoint(x: screen.maxX, y: screen.maxY)] {
                    XCTAssertTrue(screen.contains(NSRect(origin: HeldWorkspaceWheelLayout.origin(
                        size: size, pointer: pointer, visibleFrame: screen), size: size)))
                }
            }
            XCTAssertFalse(HeldWorkspaceWheelLayout.fits(in: NSRect(x: 0, y: 0, width: 384, height: 480), geometry: geometry),
                "Use the existing table instead of shrinking a many-display wheel below the readable scale")
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
