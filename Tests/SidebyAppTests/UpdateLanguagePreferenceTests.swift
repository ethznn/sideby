import XCTest
import SidebyCore
@testable import SidebyApp

final class UpdateLanguagePreferenceTests: XCTestCase {
    func testLanguagePreferenceUsesOnlyTheSuppliedAppDomain() {
        let suite = "sideby-update-language-test-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let original = UserDefaults.standard.object(forKey: "AppleLanguages") as? [String]
        UpdateLanguagePreference.apply(.korean, defaults: preferences)
        XCTAssertEqual(preferences.stringArray(forKey: "AppleLanguages"), ["ko"])
        UpdateLanguagePreference.apply(.english, defaults: preferences)
        XCTAssertEqual(preferences.stringArray(forKey: "AppleLanguages"), ["en"])
        XCTAssertEqual(UserDefaults.standard.object(forKey: "AppleLanguages") as? [String], original)
    }

    func testSparkleLocalizationMapsToSupportedAppLanguages() {
        XCTAssertEqual(UpdateLanguagePreference.language(for: ["ko"]), .korean)
        XCTAssertEqual(UpdateLanguagePreference.language(for: ["ko-KR", "en"]), .korean)
        XCTAssertEqual(UpdateLanguagePreference.language(for: ["en", "ko"]), .english)
        XCTAssertEqual(UpdateLanguagePreference.language(for: []), .english)
    }
}
