public struct AppExceptionList: Equatable, Codable, Sendable {
    public var disabledBundleIdentifiers: Set<String>

    public init(disabledBundleIdentifiers: Set<String> = []) {
        self.disabledBundleIdentifiers = disabledBundleIdentifiers
    }
}

public struct AppExceptionPolicy: Sendable {
    private let exceptionList: AppExceptionList

    public init(exceptionList: AppExceptionList) {
        self.exceptionList = exceptionList
    }

    public func allowsSwipe(in app: ActiveAppInfo?) -> Bool {
        guard let app else {
            return true
        }

        return !exceptionList.disabledBundleIdentifiers.contains(app.bundleIdentifier)
    }
}
