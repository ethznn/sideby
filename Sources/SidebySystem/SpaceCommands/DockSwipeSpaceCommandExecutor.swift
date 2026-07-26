import CoreGraphics
import SidebyCore

public struct DockSwipeGestureDescriptor: Equatable, Sendable {
    public let dockControlType: Int64
    public let hidType: Int64
    public let motion: Int64
    public let progress: Double
    public let velocityX: Double
    public let beganPhase: Int64
    public let endedPhase: Int64

    public init(
        dockControlType: Int64,
        hidType: Int64,
        motion: Int64,
        progress: Double,
        velocityX: Double,
        beganPhase: Int64,
        endedPhase: Int64
    ) {
        self.dockControlType = dockControlType
        self.hidType = hidType
        self.motion = motion
        self.progress = progress
        self.velocityX = velocityX
        self.beganPhase = beganPhase
        self.endedPhase = endedPhase
    }

    public static func make(for command: SwitchCommand) -> Self {
        let sign: Double
        switch command {
        case .next:
            sign = 1.0
        case .previous:
            sign = -1.0
        }

        return Self(
            dockControlType: 30,
            hidType: 23,
            motion: 1,
            progress: sign,
            velocityX: 9999.0 * sign,
            beganPhase: 1,
            endedPhase: 4
        )
    }
}

public protocol DockSwipeEventPosting: Sendable {
    func post(_ descriptor: DockSwipeGestureDescriptor) -> Bool
}

struct AnyDockSwipeEventPoster: DockSwipeEventPosting {
    private let poster: any DockSwipeEventPosting

    init(_ poster: any DockSwipeEventPosting) {
        self.poster = poster
    }

    func post(_ descriptor: DockSwipeGestureDescriptor) -> Bool {
        poster.post(descriptor)
    }
}

public struct DockSwipeSpaceCommandExecutor<Poster: DockSwipeEventPosting>: SpaceCommandExecuting {
    private let poster: Poster

    public init(poster: Poster) {
        self.poster = poster
    }

    public func execute(_ command: SwitchCommand) -> Bool {
        poster.post(DockSwipeGestureDescriptor.make(for: command))
    }
}

enum DockSwipeEventTap: Equatable, Sendable {
    case session
}

protocol CGDockSwipeEventWriting: Sendable {
    func makeEvent() -> (any CGDockSwipeEventWritingEvent)?
}

protocol CGDockSwipeEventWritingEvent: Sendable {
    func setIntegerValue(field: UInt32, value: Int64) -> Bool
    func setDoubleValue(field: UInt32, value: Double) -> Bool
    func post(tap: DockSwipeEventTap) -> Bool
}

private struct CGDockSwipeEventWriter: CGDockSwipeEventWriting {
    func makeEvent() -> (any CGDockSwipeEventWritingEvent)? {
        guard let event = CGEvent(source: nil) else {
            return nil
        }
        return CGDockSwipeWritableEvent(event: event)
    }
}

private final class CGDockSwipeWritableEvent: CGDockSwipeEventWritingEvent, @unchecked Sendable {
    private let event: CGEvent

    init(event: CGEvent) {
        self.event = event
    }

    func setIntegerValue(field: UInt32, value: Int64) -> Bool {
        guard let eventField = CGEventField(rawValue: field)
        else {
            return false
        }
        event.setIntegerValueField(eventField, value: value)
        return true
    }

    func setDoubleValue(field: UInt32, value: Double) -> Bool {
        guard let eventField = CGEventField(rawValue: field)
        else {
            return false
        }
        event.setDoubleValueField(eventField, value: value)
        return true
    }

    func post(tap: DockSwipeEventTap) -> Bool {
        switch tap {
        case .session:
            event.post(tap: .cgSessionEventTap)
        }
        return true
    }
}

public struct CGDockSwipeEventPoster: DockSwipeEventPosting {
    private let writer: any CGDockSwipeEventWriting
    private let hasOrRequestPostEventAccess: @Sendable () -> Bool

    public init() {
        self.init(
            writer: CGDockSwipeEventWriter(),
            hasOrRequestPostEventAccess: {
                CGPreflightPostEventAccess() || CGRequestPostEventAccess()
            }
        )
    }

    init(
        writer: any CGDockSwipeEventWriting,
        hasOrRequestPostEventAccess: @escaping @Sendable () -> Bool
    ) {
        self.writer = writer
        self.hasOrRequestPostEventAccess = hasOrRequestPostEventAccess
    }

    public func post(_ descriptor: DockSwipeGestureDescriptor) -> Bool {
        guard hasOrRequestPostEventAccess(),
              let event = writer.makeEvent()
        else {
            return false
        }

        // Private event-field technique adapted from Yabai's space_manager_focus_space_using_gesture.
        return event.setIntegerValue(field: 55, value: descriptor.dockControlType)
            && event.setIntegerValue(field: 110, value: descriptor.hidType)
            && event.setIntegerValue(field: 123, value: descriptor.motion)
            && event.setDoubleValue(field: 124, value: descriptor.progress)
            && event.setDoubleValue(field: 129, value: descriptor.velocityX)
            && event.setIntegerValue(field: 132, value: descriptor.beganPhase)
            && event.post(tap: .session)
            && event.setIntegerValue(field: 132, value: descriptor.endedPhase)
            && event.post(tap: .session)
    }
}
