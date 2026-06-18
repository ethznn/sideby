import AppKit
import CoreGraphics
import SidebyCore

public struct DisplaySnapshot: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let name: String
    public let isPrimary: Bool
    public let isBuiltin: Bool
    public let vendorNumber: UInt32
    public let modelNumber: UInt32
    public let serialNumber: UInt32
    public let frame: DisplayFrame?

    public init(
        displayID: CGDirectDisplayID,
        name: String,
        isPrimary: Bool,
        isBuiltin: Bool,
        vendorNumber: UInt32,
        modelNumber: UInt32,
        serialNumber: UInt32,
        frame: DisplayFrame? = nil
    ) {
        self.displayID = displayID
        self.name = name
        self.isPrimary = isPrimary
        self.isBuiltin = isBuiltin
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.frame = frame
    }
}

public enum DisplayLayoutMapper {
    public static func layout(from snapshots: [DisplaySnapshot]) -> DisplayLayout {
        DisplayLayout(
            displays: snapshots.map { snapshot in
                DisplayInfo(
                    id: stableID(for: snapshot),
                    name: snapshot.name,
                    isPrimary: snapshot.isPrimary,
                    isBuiltin: snapshot.isBuiltin,
                    frame: snapshot.frame
                )
            }
        )
    }

    public static func stableID(for snapshot: DisplaySnapshot) -> String {
        [
            String(snapshot.vendorNumber),
            String(snapshot.modelNumber),
            String(snapshot.serialNumber),
            String(snapshot.displayID)
        ].joined(separator: "-")
    }

    public static func stableIDsByUUID(
        snapshots: [DisplaySnapshot],
        uuidForDisplayID: (CGDirectDisplayID) -> String?
    ) -> [String: String] {
        var mapping: [String: String] = [:]
        for snapshot in snapshots {
            guard let uuid = uuidForDisplayID(snapshot.displayID) else {
                continue
            }
            mapping[uuid] = stableID(for: snapshot)
        }
        return mapping
    }

    public static func instantCaptureDisplays(
        selectedDisplayIDs: Set<String>,
        displayLayout: DisplayLayout,
        layouts: [DisplaySpaceLayout],
        stableIDsByUUID: [String: String]
    ) -> [InstantCaptureDisplay] {
        let layoutsByStableID: [String: DisplaySpaceLayout] = layouts.reduce(into: [:]) {
            result, layout in
            if let stableID = stableIDsByUUID[layout.displayUUID] {
                result[stableID] = layout
            }
        }

        return displayLayout.displays.compactMap { display in
            guard selectedDisplayIDs.contains(display.id),
                  let layout = layoutsByStableID[display.id],
                  let currentIndex = layout.spaceIDs.firstIndex(of: layout.currentSpaceID)
            else {
                return nil
            }
            return InstantCaptureDisplay(
                displayID: display.id,
                spaceCount: layout.spaceIDs.count,
                currentSpaceIndex: currentIndex
            )
        }
    }

    public static func displayUUID(for displayID: CGDirectDisplayID) -> String? {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, cfUUID) as String?
    }
}

public struct MacDisplayObserver: DisplayObserving {
    public init() {}

    public func currentLayout() -> DisplayLayout {
        DisplayLayoutMapper.layout(from: currentSnapshots())
    }

    public func currentSnapshots() -> [DisplaySnapshot] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else {
            return []
        }

        return displayIDs.map { id in
            let bounds = CGDisplayBounds(id)
            return DisplaySnapshot(
                displayID: id,
                name: displayName(for: id),
                isPrimary: CGDisplayIsMain(id) != 0,
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                vendorNumber: CGDisplayVendorNumber(id),
                modelNumber: CGDisplayModelNumber(id),
                serialNumber: CGDisplaySerialNumber(id),
                frame: DisplayFrame(
                    x: Double(bounds.origin.x),
                    y: Double(bounds.origin.y),
                    width: Double(bounds.width),
                    height: Double(bounds.height)
                )
            )
        }
    }

    private func displayName(for displayID: CGDirectDisplayID) -> String {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screen = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[screenNumberKey] as? NSNumber else {
                return false
            }

            return number.uint32Value == displayID
        }) else {
            return "Display \(displayID)"
        }

        return screen.localizedName
    }
}
