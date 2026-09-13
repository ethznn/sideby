/// Keeps a field's raw typing separate from the domain's normalized name.
public struct NativeNameEditingState: Equatable {
    public private(set) var draft: String
    public var isFocused = false {
        didSet {
            if !isFocused { draft = latestExternalValue }
        }
    }
    private var latestExternalValue: String

    public init(value: String) {
        draft = value
        latestExternalValue = value
    }

    public mutating func edit(_ value: String) {
        draft = value
        // Preserve the newest edit until the model acknowledges it.
        latestExternalValue = value
    }

    public mutating func receiveExternalValue(_ value: String) {
        latestExternalValue = value
        if !isFocused { draft = value }
    }
}
