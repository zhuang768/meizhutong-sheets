import XCTest
@testable import YouthAISubsidy

final class SubsidyEstimatorTests: XCTestCase {
    func testGeneralYouthIsHalfWithCap() {
        var draft = SyntheticFixtures.fillableGeneral()
        draft.purchase.twdPaidAmount = DecimalString(640)
        let estimate = SubsidyEstimator.estimate(for: draft)
        XCTAssertEqual(NSDecimalNumber(decimal: estimate.amount).intValue, 320)
        XCTAssertTrue(estimate.hints.contains(where: { $0.contains("非核定金額") }))
    }

    func testSpecialTargetUsesNinetyPercent() {
        var draft = SyntheticFixtures.fillableSpecial()
        draft.purchase.twdPaidAmount = DecimalString(1800)
        let estimate = SubsidyEstimator.estimate(for: draft)
        XCTAssertEqual(NSDecimalNumber(decimal: estimate.amount).intValue, 1620)
    }

    func testCapApplies() {
        var draft = SyntheticFixtures.fillableGeneral()
        draft.purchase.twdPaidAmount = DecimalString(20000)
        let estimate = SubsidyEstimator.estimate(for: draft)
        XCTAssertEqual(NSDecimalNumber(decimal: estimate.amount).intValue, 3000)
    }

    func testSharedContractStatusesMatchTeammateList() {
        let raw = CaseStatus.allCases.map(\.rawValue)
        XCTAssertEqual(
            Set(raw),
            ["draft", "submitted", "needs_documents", "under_manual_review", "approved", "rejected"]
        )
    }

    func testLocalSubmitDoesNotCreateApproval() async throws {
        DemoCaseStore.shared.resetOwnCases()
        var draft = SyntheticFixtures.fillableGeneral()
        draft.caseId = "DRAFT-TEST-SUBMIT"
        draft.documents = FormValidator.requiredDocumentTypes(for: draft).map { type in
            CaseDocument(
                id: type.rawValue,
                type: type,
                fileName: "\(type.rawValue).png",
                localRelativePath: "\(type.rawValue).png",
                isSynthetic: true,
                attachedAt: Date()
            )
        }
        let result = try await DemoCaseStore.shared.submit(draft)
        XCTAssertEqual(result.status, .submitted)
        XCTAssertFalse(result.status.isTerminalDecision)
    }
}
