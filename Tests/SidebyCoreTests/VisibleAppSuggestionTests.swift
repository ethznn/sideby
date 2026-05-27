import XCTest
@testable import SidebyCore

final class VisibleAppSuggestionTests: XCTestCase {
    func testSuggestionPrefersWindowTitleWhenAvailable() {
        let suggestion = VisibleAppSuggestion(
            displayID: "built-in",
            appName: "Xcode",
            windowTitle: "SidebyApp.swift",
            source: .accessibility
        )

        XCTAssertEqual(suggestion.appLabel, "Xcode")
        XCTAssertEqual(suggestion.titleLabel, "SidebyApp.swift")
        XCTAssertEqual(suggestion.combinedLabel, "Xcode - SidebyApp.swift")
    }

    func testSuggestionFallsBackToAppNameWhenTitleIsEmpty() {
        let suggestion = VisibleAppSuggestion(
            displayID: "external",
            appName: "Safari",
            windowTitle: "   ",
            source: .windowList
        )

        XCTAssertEqual(suggestion.appLabel, "Safari")
        XCTAssertNil(suggestion.titleLabel)
        XCTAssertEqual(suggestion.combinedLabel, "Safari")
    }
}
