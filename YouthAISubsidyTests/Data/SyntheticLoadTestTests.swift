import XCTest
@testable import YouthAISubsidy

final class RecordingSpreadsheetRepository: CaseRepository, @unchecked Sendable {
    var writesToSpreadsheet: Bool { true }
    var submitted: [SubsidyCase] = []
    var failAfter = Int.max

    func listCases() async throws -> [SubsidyCase] { submitted }
    func loadCase(id: String) async throws -> SubsidyCase {
        guard let item = submitted.first(where: { $0.caseId == id }) else { throw CaseRepositoryError.missingCase }
        return item
    }
    func saveDraft(_ draft: SubsidyCase) async throws -> SubsidyCase { draft }
    func submit(_ draft: SubsidyCase) async throws -> SubsidyCase {
        if submitted.count >= failAfter {
            throw CaseRepositoryError.remoteFailed("試算表收件服務尚未回覆，資料仍留在手機；請稍後重試。")
        }
        var copy = draft
        copy.status = .submitted
        copy.caseId = "MZT-SHEET-\(String(format: "%02d", submitted.count + 1))"
        submitted.append(copy)
        return copy
    }
}

@MainActor
final class SyntheticLoadTestTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("YouthAISubsidy-batch-\(UUID().uuidString)", isDirectory: true)
        LocalAttachmentStore.overrideDirectory = folder
        DemoCaseStore.shared.resetOwnCases()
        SyntheticLoadTest.resetProgress()
    }

    override func tearDown() {
        LocalAttachmentStore.removeAll()
        LocalAttachmentStore.overrideDirectory = nil
        DemoCaseStore.shared.resetOwnCases()
        SyntheticLoadTest.resetProgress()
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    func testBatchMatchesExcelFirstTwentyScenarios() throws {
        XCTAssertEqual(SyntheticLoadTest.datasetTotal, 50_000)
        XCTAssertEqual(SyntheticLoadTest.rows.count, 20)
        XCTAssertEqual(SyntheticLoadTest.rows.map(\.scenario), [
            "pass", "passSpecial", "passCultural", "passMonthly", "passProxy",
            "passXiangshan", "passSyntheticId", "passHighAmount",
            "notResident", "prepaid", "aggregator", "reseller", "vendorRegion",
            "ageTooOld", "ageTooYoung", "purchaseTooEarly", "purchaseTooLate",
            "applyLateMonthly", "badId", "missingId"
        ])
        XCTAssertEqual(SyntheticLoadTest.rows[5].documentVariant, .idMismatch)
        XCTAssertEqual(SyntheticLoadTest.rows[6].documentVariant, .receiptMismatch)
        XCTAssertEqual(SyntheticLoadTest.rows[7].documentVariant, .unsignedAffidavit)

        let first = try XCTUnwrap(SyntheticLoadTest.makeCase(SyntheticLoadTest.rows[0]))
        XCTAssertEqual(first.caseId, "MZT-LOADTEST-000001")
        XCTAssertEqual(first.applicant.fullName, "合成申請人-00001")
        XCTAssertEqual(first.formFields.nationalID, "A100000001")
        XCTAssertEqual(first.purchase.toolName, "ChatGPT Plus")
        XCTAssertEqual(first.status, .draft)

        let missingId = try XCTUnwrap(SyntheticLoadTest.makeCase(SyntheticLoadTest.rows[19]))
        XCTAssertEqual(missingId.formFields.nationalID, "")
        XCTAssertNotEqual(missingId.formFields.nationalID, "TEST-ID-ONLY")
    }

    func testMismatchImagesDifferFromMatchingOnes() throws {
        let item = try XCTUnwrap(SyntheticLoadTest.makeCase(SyntheticLoadTest.rows[0]))
        let idMatch = SyntheticDocumentFactory.makeImage(type: .idFront, item: item, variant: .match)
        let idMismatch = SyntheticDocumentFactory.makeImage(type: .idFront, item: item, variant: .idMismatch)
        let receiptMatch = SyntheticDocumentFactory.makeImage(type: .officialReceipt, item: item, variant: .match)
        let receiptMismatch = SyntheticDocumentFactory.makeImage(type: .officialReceipt, item: item, variant: .receiptMismatch)
        let signed = SyntheticDocumentFactory.makeImage(type: .signedAffidavit, item: item, variant: .match)
        let unsigned = SyntheticDocumentFactory.makeImage(type: .signedAffidavit, item: item, variant: .unsignedAffidavit)
        XCTAssertEqual(DetectedImageFormat.detect(idMatch), .jpeg)
        XCTAssertNotEqual(idMatch, idMismatch)
        XCTAssertNotEqual(receiptMatch, receiptMismatch)
        XCTAssertNotEqual(signed, unsigned)
    }

    func testLocalDemoAndMissingCredentialNeverPretendBatchSuccess() async {
        let local = ApplicationFlowModel(repository: DemoCaseStore.shared)
        await local.submitSpreadsheetBatch()
        XCTAssertEqual(SyntheticLoadTest.submittedIds().count, 0)
        XCTAssertTrue(local.banner?.contains("沒有寫入試算表") == true)

        let missing = ApplicationFlowModel(repository: UnconfiguredSubmissionRepository())
        await missing.submitSpreadsheetBatch()
        XCTAssertEqual(SyntheticLoadTest.submittedIds().count, 0)
        XCTAssertTrue(missing.banner?.contains("沒有寫入試算表") == true)
        XCTAssertTrue(missing.banner?.contains("憑證") == true)
    }

    func testSpreadsheetBatchSubmitsTwentyAndKeepsProgressOnFailure() async throws {
        let repository = RecordingSpreadsheetRepository()
        let model = ApplicationFlowModel(repository: repository)
        await model.submitSpreadsheetBatch()
        XCTAssertEqual(repository.submitted.count, 20)
        XCTAssertEqual(SyntheticLoadTest.submittedIds().count, 20)
        XCTAssertEqual(model.spreadsheetBatchSubmittedCount, 20)
        XCTAssertTrue(model.banner?.contains("試算表已收妥 20 筆") == true)
        XCTAssertTrue(repository.submitted.allSatisfy { $0.status == .submitted && !$0.status.isTerminalDecision })
        XCTAssertTrue(repository.submitted.allSatisfy { !$0.documents.isEmpty })
        XCTAssertEqual(repository.submitted[5].documents.contains { $0.type == .idFront }, true)

        await model.submitSpreadsheetBatch()
        XCTAssertEqual(repository.submitted.count, 20)
        XCTAssertTrue(model.banner?.contains("不會新增第二筆") == true)

        SyntheticLoadTest.resetProgress()
        repository.submitted = []
        repository.failAfter = 2
        let retry = ApplicationFlowModel(repository: repository)
        await retry.submitSpreadsheetBatch()
        XCTAssertEqual(repository.submitted.count, 2)
        XCTAssertEqual(SyntheticLoadTest.submittedIds().count, 2)
        XCTAssertTrue(retry.banner?.contains("已送出 2 筆後中斷") == true)
        XCTAssertTrue(retry.banner?.contains("不會假裝成功") == true)
    }
}
