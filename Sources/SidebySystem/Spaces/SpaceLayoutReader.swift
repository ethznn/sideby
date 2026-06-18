import Foundation
import Darwin

public struct DisplaySpaceLayout: Equatable, Sendable {
    public let displayUUID: String
    public let spaceIDs: [UInt64]
    public let currentSpaceID: UInt64

    public init(displayUUID: String, spaceIDs: [UInt64], currentSpaceID: UInt64) {
        self.displayUUID = displayUUID
        self.spaceIDs = spaceIDs
        self.currentSpaceID = currentSpaceID
    }

    /// Parses the bridged payload of SLSCopyManagedDisplaySpaces. Some
    /// mirrored displays can appear without independent Spaces; those entries
    /// are ignored so valid display layouts remain usable.
    public static func displays(
        fromManagedDisplaySpaces payload: [[String: Any]]
    ) -> [DisplaySpaceLayout]? {
        let layouts = payload.compactMap(Self.display(fromManagedDisplaySpaceEntry:))
        return layouts.isEmpty ? nil : layouts
    }

    private static func display(fromManagedDisplaySpaceEntry entry: [String: Any]) -> DisplaySpaceLayout? {
        guard
            let uuid = entry["Display Identifier"] as? String,
            let current = entry["Current Space"] as? [String: Any],
            let currentID = (current["ManagedSpaceID"] as? NSNumber).flatMap(UInt64.init(exactly:)),
            let spaces = entry["Spaces"] as? [[String: Any]],
            !spaces.isEmpty
        else {
            return nil
        }

        let spaceIDs = spaces.compactMap { space in
            (space["ManagedSpaceID"] as? NSNumber).flatMap(UInt64.init(exactly:))
        }
        guard spaceIDs.count == spaces.count,
              spaceIDs.contains(currentID)
        else {
            return nil
        }

        return DisplaySpaceLayout(
            displayUUID: uuid,
            spaceIDs: spaceIDs,
            currentSpaceID: currentID
        )
    }
}

public protocol SpaceLayoutReading: Sendable {
    /// Returns the per-display Space layout, or nil when unavailable.
    func readLayout() -> [DisplaySpaceLayout]?
}

public struct SLSSpaceLayoutReader: SpaceLayoutReading {
    public init() {}

    public func readLayout() -> [DisplaySpaceLayout]? {
        guard let symbols = Self.symbols else {
            return nil
        }
        guard
            let raw = symbols.copyManagedDisplaySpaces(symbols.mainConnectionID())?
                .takeRetainedValue(),
            let payload = raw as? [[String: Any]]
        else {
            return nil
        }
        return DisplaySpaceLayout.displays(fromManagedDisplaySpaces: payload)
    }

    private struct Symbols {
        let mainConnectionID: @convention(c) () -> UInt32
        let copyManagedDisplaySpaces: @convention(c) (UInt32) -> Unmanaged<CFArray>?
    }

    private static let symbols: Symbols? = {
        guard
            let handle = dlopen(
                "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                RTLD_NOW
            ),
            let mainPointer = dlsym(handle, "SLSMainConnectionID"),
            let copyPointer = dlsym(handle, "SLSCopyManagedDisplaySpaces")
        else {
            return nil
        }
        return Symbols(
            mainConnectionID: unsafeBitCast(
                mainPointer,
                to: (@convention(c) () -> UInt32).self
            ),
            copyManagedDisplaySpaces: unsafeBitCast(
                copyPointer,
                to: (@convention(c) (UInt32) -> Unmanaged<CFArray>?).self
            )
        )
    }()
}
