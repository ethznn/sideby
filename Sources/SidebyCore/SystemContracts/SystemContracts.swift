public protocol PermissionServicing: Sendable {
    var currentState: PermissionState { get }
    func requestAccessPrompt()
}

public protocol SpaceCommandExecuting: Sendable {
    @discardableResult
    func execute(_ command: SwitchCommand) -> Bool
}

public protocol DisplayObserving: Sendable {
    func currentLayout() -> DisplayLayout
}

public protocol VisibleAppSuggestionProviding: Sendable {
    func suggestions(for displayLayout: DisplayLayout) -> [VisibleAppSuggestion]
}

public struct ActiveAppInfo: Equatable, Sendable {
    public let bundleIdentifier: String
    public let localizedName: String?

    public init(bundleIdentifier: String, localizedName: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }
}

public protocol ActiveAppObserving: Sendable {
    func currentApp() -> ActiveAppInfo?
}

public protocol LoginItemServicing: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ isEnabled: Bool) throws
}
