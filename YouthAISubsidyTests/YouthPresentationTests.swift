import XCTest
@testable import YouthAISubsidy

final class YouthPresentationTests: XCTestCase {
    func testPrecheckGapsWithoutNeedsDocumentsAreNotOfficialSupplement() {
        var item = SyntheticFixtures.fillableGeneral()
        item.status = .submitted
        item.precheck = Precheck(
            eligibilityHints: ["內部預檢：請勿顯示給青年。"],
            documentGaps: ["內部預檢缺件，不能當成補件通知。"],
            estimatedSubsidyTWD: DecimalString(320),
            disclaimer: "內部預檢",
            source: "synthetic-precheck"
        )

        XCTAssertEqual(YouthPresentation.supplementDisplay(for: item), .none)
        XCTAssertFalse(item.precheck?.documentGaps.isEmpty ?? true)
    }

    func testNeedsDocumentsWithoutDedicatedYouthNoticeDoesNotUsePrecheckGaps() {
        var item = SyntheticFixtures.fillableGeneral()
        item.caseId = "CASE-LOCAL-NEEDS-DOCS"
        item.status = .needsDocuments
        item.precheck = Precheck(
            eligibilityHints: ["內部預檢結論"],
            documentGaps: ["這不該出現在青年補件通知。"],
            estimatedSubsidyTWD: DecimalString(320),
            disclaimer: "內部",
            source: "synthetic-precheck"
        )

        XCTAssertEqual(YouthPresentation.supplementDisplay(for: item), .awaitingOfficialExplanation)
        if case .syntheticDemo = YouthPresentation.supplementDisplay(for: item) {
            XCTFail("Must not promote precheck gaps to a supplement notice")
        }
    }

    func testLabeledSyntheticSupplementCaseIsExplicit() {
        let fixture = SyntheticFixtures.specialNeedsDocuments()
        XCTAssertEqual(fixture.status, .needsDocuments)
        XCTAssertEqual(
            YouthPresentation.supplementDisplay(for: fixture),
            .syntheticDemo(["官方收據未見軟體公司名稱（合成補件示範，非正式承辦通知）。"])
        )
    }
}
