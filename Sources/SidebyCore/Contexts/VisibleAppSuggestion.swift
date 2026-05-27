import Foundation

public enum VisibleAppSuggestionSource: String, Codable, Equatable, Sendable {
    case accessibility
    case windowList
}

public struct VisibleAppSuggestion: Equatable, Codable, Identifiable, Sendable {
    public let displayID: String
    public let appName: String
    public let windowTitle: String?
    public let source: VisibleAppSuggestionSource

    public init(
        displayID: String,
        appName: String,
        windowTitle: String?,
        source: VisibleAppSuggestionSource
    ) {
        self.displayID = displayID
        self.appName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.windowTitle = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
    }

    public var id: String {
        displayID
    }

    public var appLabel: String {
        appName
    }

    public var titleLabel: String? {
        guard let windowTitle,
              !windowTitle.isEmpty
        else {
            return nil
        }

        return windowTitle
    }

    public var combinedLabel: String {
        guard let titleLabel else {
            return appName
        }

        return "\(appName) - \(titleLabel)"
    }
}
