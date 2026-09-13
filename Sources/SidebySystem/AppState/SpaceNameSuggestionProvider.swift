import CoreGraphics
import ApplicationServices
import Darwin
import Foundation
import SidebyCore

/// Suggestions from window metadata, not native macOS desktop names.
public protocol SpaceNameSuggestionProviding: Sendable {
    func names(for layout: DisplayLayout, spaceIDsByDisplayID: [String: [UInt64]]) -> [String: [Int: String]]
}

struct SpaceWindowNameCandidate: Sendable {
    let spaceIDs: Set<UInt64>
    let window: VisibleWindowCandidate
}

enum SpaceNameSuggestionResolver {
    static func names(windows: [SpaceWindowNameCandidate], layout: DisplayLayout,
                      spaceIDsByDisplayID: [String: [UInt64]]) -> [String: [Int: String]] {
        var result: [String: [Int: String]] = [:]
        for display in layout.displays {
            for (index, spaceID) in (spaceIDsByDisplayID[display.id] ?? []).enumerated() {
                // A window assigned to every desktop cannot identify an individual workspace.
                let candidates = windows.filter { $0.spaceIDs == [spaceID] }.map(\.window)
                guard let suggestion = VisibleAppSuggestionResolver.suggestion(for: display,
                    accessibilitySuggestion: nil, windows: candidates) else { continue }
                let name = (suggestion.titleLabel ?? suggestion.appLabel)
                    .components(separatedBy: .newlines).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { result[display.id, default: [:]][index] = String(name.prefix(120)) }
            }
        }
        return result
    }
}

public struct MacSpaceNameSuggestionProvider: SpaceNameSuggestionProviding {
    public init() {}

    public func names(for layout: DisplayLayout, spaceIDsByDisplayID: [String: [UInt64]]) -> [String: [Int: String]] {
        guard let symbols = Self.symbols,
              let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [:] }
        let connection = symbols.mainConnectionID()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let missingTitlePIDs = Set(windows.compactMap { dictionary -> Int32? in
            guard (dictionary[kCGWindowLayer as String] as? Int) == 0,
                  (dictionary[kCGWindowName as String] as? String)?.isEmpty != false,
                  let pid = dictionary[kCGWindowOwnerPID as String] as? Int32, pid != ownPID else { return nil }
            return pid
        })
        let accessibleTitles = AXDesktopWindowTitles.read(processIDs: missingTitlePIDs)
        let candidates = windows.compactMap { dictionary -> SpaceWindowNameCandidate? in
            guard (dictionary[kCGWindowLayer as String] as? Int) == 0,
                  let pid = dictionary[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let owner = dictionary[kCGWindowOwnerName as String] as? String,
                  let number = dictionary[kCGWindowNumber as String] as? NSNumber,
                  let boundsDictionary = dictionary[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.width > 0, bounds.height > 0,
                  let raw = symbols.copySpacesForWindows(connection, 7, [number] as CFArray)?.takeRetainedValue(),
                  let spaces = raw as? [NSNumber] else { return nil }
            return .init(spaceIDs: Set(spaces.map(\.uint64Value)), window: .init(ownerName: owner,
                windowTitle: (dictionary[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? accessibleTitles[number.uint32Value], bounds: bounds,
                processIdentifier: pid, layer: 0))
        }
        return SpaceNameSuggestionResolver.names(windows: candidates, layout: layout, spaceIDsByDisplayID: spaceIDsByDisplayID)
    }

    private struct Symbols {
        let mainConnectionID: @convention(c) () -> UInt32
        let copySpacesForWindows: @convention(c) (UInt32, UInt32, CFArray) -> Unmanaged<CFArray>?
    }

    // Same optional private-framework boundary as SLSSpaceLayoutReader. Unavailable symbols
    // or filtered metadata leave existing names alone. No screenshots or permission prompts.
    private static let symbols: Symbols? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else { return nil }
        guard let main = dlsym(handle, "SLSMainConnectionID"),
              let copy = dlsym(handle, "SLSCopySpacesForWindows") else {
            dlclose(handle)
            return nil
        }
        return Symbols(mainConnectionID: unsafeBitCast(main, to: (@convention(c) () -> UInt32).self),
            copySpacesForWindows: unsafeBitCast(copy, to: (@convention(c) (UInt32, UInt32, CFArray) -> Unmanaged<CFArray>?).self))
    }()
}

private enum AXDesktopWindowTitles {
    private typealias WindowIDReader = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError
    private static let windowIDReader: WindowIDReader? = {
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW) else { return nil }
        guard let pointer = dlsym(handle, "_AXUIElementGetWindow") else { dlclose(handle); return nil }
        return unsafeBitCast(pointer, to: WindowIDReader.self)
    }()

    static func read(processIDs: Set<Int32>) -> [UInt32: String] {
        guard AXIsProcessTrusted(), let windowIDReader else { return [:] }
        var result: [UInt32: String] = [:]
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        for pid in processIDs.sorted() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.1)
            var value: CFArray?
            guard AXUIElementCopyAttributeValues(app, kAXWindowsAttribute as CFString, 0, 100, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for window in windows {
                guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                AXUIElementSetMessagingTimeout(window, 0.05)
                var id: UInt32 = 0
                var title: CFTypeRef?
                guard windowIDReader(window, &id) == .success,
                      AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success,
                      let name = title as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                result[id] = name
            }
        }
        return result
    }
}
