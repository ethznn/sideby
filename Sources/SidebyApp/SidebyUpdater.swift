import Combine
import Foundation
import SidebyCore
import Sparkle

@MainActor
final class SidebyUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var languageRequiresRestart = false

    private let controller: SPUStandardUpdaterController
    private var cancellables: Set<AnyCancellable> = []

    init(model: SidebyAppModel) {
        // App-scoped language preference, never the user's global macOS language.
        UpdateLanguagePreference.apply(model.settings.language)
        let launchLanguage = UpdateLanguagePreference.language(
            for: Bundle(for: SPUStandardUserDriver.self).preferredLocalizations)
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
            }
            .store(in: &cancellables)

        model.$settings.map(\.language).removeDuplicates()
            .sink { [weak self] language in
                UpdateLanguagePreference.apply(language)
                self?.languageRequiresRestart = language != launchLanguage
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

enum UpdateLanguagePreference {
    static func apply(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        let languages = [language.rawValue]
        if defaults.stringArray(forKey: "AppleLanguages") != languages {
            defaults.set(languages, forKey: "AppleLanguages")
        }
    }

    static func language(for localizations: [String]) -> AppLanguage {
        localizations.first?.split(separator: "-").first == "ko" ? .korean : .english
    }
}
