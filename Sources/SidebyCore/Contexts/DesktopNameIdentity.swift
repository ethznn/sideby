import Foundation

/// A desktop bookmark, never an ordinal or a transient WindowServer handle.
public struct DesktopNameIdentity: Hashable, Sendable {
    public let storageKey: String

    public init?(spaceKey: String, displayID: String) {
        if spaceKey.hasPrefix("uuid:"), let uuid = UUID(uuidString: String(spaceKey.dropFirst(5))) {
            storageKey = "uuid:" + uuid.uuidString
        } else if spaceKey == "default-desktop", displayID.hasPrefix("uuid:"),
                  let uuid = UUID(uuidString: String(displayID.dropFirst(5))) {
            // macOS explicitly uses an empty UUID for the display's default desktop.
            storageKey = "default-desktop:" + uuid.uuidString
        } else {
            return nil
        }
    }
}

public enum DesktopNameValidation: Equatable, Sendable {
    case valid(String)
    case empty
    case tooLong
    case multipleLines

    public static let maximumLength = 60

    public static func validate(_ raw: String) -> Self {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .empty }
        guard name.count <= maximumLength else { return .tooLong }
        // Foundation's controlCharacters includes format scalars such as the ZWJ
        // used in family emoji. Reject actual controls, not grapheme joiners.
        guard !name.unicodeScalars.contains(where: {
            $0.properties.generalCategory == .control || CharacterSet.newlines.contains($0)
        }) else { return .multipleLines }
        return .valid(name)
    }
}
