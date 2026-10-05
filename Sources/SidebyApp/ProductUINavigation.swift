import Combine

enum ProductSettingsPane: String, CaseIterable, Identifiable {
    case workspaces, input, permissions, general
    var id: Self { self }
}

enum ProductOnboardingStage: Int, CaseIterable {
    case preparation, displays, workspaces, roundTrip
}

enum ProductReturnDestination: Equatable {
    case daily, onboarding
}

struct ProductSettingsRoute: Equatable {
    var pane: ProductSettingsPane
    var contextID: String? = nil
    var displayID: String? = nil
    var returnTo: ProductReturnDestination? = nil
}

@MainActor
final class ProductUINavigation: ObservableObject {
    @Published private(set) var settingsRoute: ProductSettingsRoute
    @Published private(set) var workspaceRoute = ProductSettingsRoute(pane: .workspaces)
    private let preferences: any ProductUIPreferences

    init(preferences: any ProductUIPreferences) {
        self.preferences = preferences
        settingsRoute = ProductSettingsRoute(pane: preferences.lastSettingsPane)
    }

    func openSettings(_ route: ProductSettingsRoute?) {
        settingsRoute = route ?? ProductSettingsRoute(pane: preferences.lastSettingsPane)
        preferences.lastSettingsPane = settingsRoute.pane
    }

    func openWorkspaces(_ route: ProductSettingsRoute = .init(pane: .workspaces)) {
        workspaceRoute = route
    }

    func selectPane(_ pane: ProductSettingsPane) {
        settingsRoute.pane = pane
        preferences.lastSettingsPane = pane
    }

    func consumeReturnDestination() -> ProductReturnDestination? {
        let destination = workspaceRoute.returnTo
        workspaceRoute.returnTo = nil
        return destination
    }
}
