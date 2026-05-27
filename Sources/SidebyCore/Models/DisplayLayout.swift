public struct DisplayFrame: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var aspectRatio: Double {
        guard height > 0 else {
            return 16.0 / 10.0
        }

        return width / height
    }
}

public struct DisplayInfo: Equatable, Sendable {
    public let id: String
    public let name: String
    public let isPrimary: Bool
    public let isBuiltin: Bool
    public let frame: DisplayFrame?

    public init(
        id: String,
        name: String,
        isPrimary: Bool,
        isBuiltin: Bool,
        frame: DisplayFrame? = nil
    ) {
        self.id = id
        self.name = name
        self.isPrimary = isPrimary
        self.isBuiltin = isBuiltin
        self.frame = frame
    }
}

public struct DisplayLayout: Equatable, Sendable {
    public let displays: [DisplayInfo]

    public init(displays: [DisplayInfo]) {
        self.displays = displays
    }

    public var displayCount: Int {
        displays.count
    }

    public var hasExternalDisplay: Bool {
        displays.contains { !$0.isBuiltin }
    }

    public var primaryDisplay: DisplayInfo? {
        displays.first { $0.isPrimary }
    }

    public var stableKey: String {
        displays
            .map(\.id)
            .sorted()
            .joined(separator: "|")
    }
}
