import AppKit
import XCTest
@testable import SidebyApp

@MainActor final class ProductApplicationDelegateTests: XCTestCase {
    func testCleanQuitDoesNotPresentSavePrompt() {
        let delegate = ProductApplicationDelegate()
        var prompted = false
        delegate.resolveUnsavedChanges = { prompted = true; return true }
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateNow)
        XCTAssertFalse(prompted)
    }

    func testKeepEditingOrFailedSaveCancelsQuitAndCanBeRetried() {
        let delegate = ProductApplicationDelegate()
        delegate.hasUnsavedChanges = { true }
        delegate.activateApplication = {}
        var mayQuit = false
        var attempts = 0
        delegate.resolveUnsavedChanges = { attempts += 1; return mayQuit }
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateCancel)
        mayQuit = true
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateNow)
        XCTAssertEqual(attempts, 2)
    }
}
