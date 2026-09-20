import XCTest
@testable import YouthAISubsidy

final class DemoCaseStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DemoCaseStore.shared.resetOwnCases()
    }

    override func tearDown() {
        DemoCaseStore.shared.resetOwnCases()
        super.tearDown()
    }

    func testOwnCaseListDoesNotIncludeSyntheticFixtures() async throws {
        let listed = try await DemoCaseStore.shared.listCases()
        XCTAssertTrue(listed.isEmpty)
        XCTAssertFalse(listed.contains(where: { SyntheticFixtures.isFixtureCaseId($0.caseId) }))
        XCTAssertEqual(DemoCaseStore.shared.listDemoFixtures().map(\.caseId), [
            SyntheticFixtures.generalId,
            SyntheticFixtures.specialId,
            SyntheticFixtures.proxyId
        ])
    }

    func testSubmitCreatesOwnLocalCaseWithoutUploadOrApproval() async throws {
        var draft = SyntheticFixtures.fillableGeneral()
        draft.caseId = "DRAFT-OWN-SUBMIT"
        draft.documents = FormValidator.requiredDocumentTypes(for: draft).map { type in
            CaseDocument(
                id: type.rawValue,
                type: type,
                fileName: "\(type.rawValue).png",
                localRelativePath: "\(type.rawValue).png",
                isSynthetic: true
            )
        }

        let result = try await DemoCaseStore.shared.submit(draft)
        XCTAssertTrue(result.caseId.hasPrefix("CASE-DEMO-LOCAL-"))
        XCTAssertEqual(result.status, .submitted)
        XCTAssertFalse(result.status.isTerminalDecision)
        XCTAssertTrue(result.documents.allSatisfy { $0.uploadedAt == nil })

        let listed = try await DemoCaseStore.shared.listCases()
        XCTAssertEqual(listed.map(\.caseId), [result.caseId])
        XCTAssertFalse(listed.contains(where: { SyntheticFixtures.isFixtureCaseId($0.caseId) }))
    }

    func testYouthPresentationHidesInternalReviewData() {
        let fixture = SyntheticFixtures.specialNeedsDocuments()
        XCTAssertTrue(YouthPresentation.isFixtureCaseId(fixture.caseId))
        XCTAssertEqual(
            YouthPresentation.supplementDisplay(for: fixture),
            .syntheticDemo(["官方收據未見軟體公司名稱（合成補件示範，非正式承辦通知）。"])
        )
        XCTAssertTrue(YouthPresentation.ownCases(from: [fixture]).isEmpty)
        XCTAssertFalse(fixture.auditEvents.isEmpty)
        XCTAssertEqual(YouthPresentation.attachmentStatusText(for: nil), "尚未填齊")
    }
}
