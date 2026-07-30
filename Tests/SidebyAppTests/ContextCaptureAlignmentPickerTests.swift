import XCTest
import SidebyCore
import SidebyUI
@testable import SidebyApp

final class ContextCaptureAlignmentPickerTests: XCTestCase {
    private let request = ProductContextCaptureAlignmentRequest(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        candidates: [
            ContextCaptureAlignmentCandidate(id: "context-2", order: 2, name: "Context 2")
        ]
    )

    func testPresentationBuildsEnglishLabelsForAlignmentCandidate() {
        let presentation = ContextCaptureAlignmentPickerPresentation(
            request: request,
            strings: SBSStrings(language: .english)
        )

        XCTAssertEqual(presentation.title, "Align captured Contexts")
        XCTAssertEqual(presentation.message, "Choose a Context shared by all selected displays.")
        XCTAssertEqual(presentation.optionLabels, ["C2 · Context 2"])
    }

    func testPresentationBuildsKoreanLabelsForAlignmentCandidate() {
        let koreanRequest = ProductContextCaptureAlignmentRequest(
            id: request.id,
            candidates: [
                ContextCaptureAlignmentCandidate(id: "context-2", order: 2, name: "컨텍스트 2")
            ]
        )

        let presentation = ContextCaptureAlignmentPickerPresentation(
            request: koreanRequest,
            strings: SBSStrings(language: .korean)
        )

        XCTAssertEqual(presentation.optionLabels, ["C2 · 컨텍스트 2"])
    }
}
