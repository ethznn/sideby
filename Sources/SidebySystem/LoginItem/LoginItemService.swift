import ServiceManagement
import SidebyCore

public struct MacLoginItemService: LoginItemServicing {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

public struct LoginItemToggleController<Service: LoginItemServicing>: Sendable {
    private let service: Service

    public init(service: Service) {
        self.service = service
    }

    public func setEnabled(_ isEnabled: Bool) throws {
        try service.setEnabled(isEnabled)
    }
}
