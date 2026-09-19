import XCTest
@testable import YouthAISubsidy

@MainActor
final class ApplicationFlowModelTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("YouthAISubsidy-model-\(UUID().uuidString)", isDirectory: true)
        LocalAttachmentStore.overrideDirectory = folder
        DemoCaseStore.shared.resetOwnCases()
    }

    override func tearDown() {
        LocalAttachmentStore.failNextWrite = false
        LocalAttachmentStore.removeAll()
        LocalAttachmentStore.overrideDirectory = nil
        DemoCaseStore.shared.resetOwnCases()
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    func testAttachLocalPhotoKeepsFileAndMarksLocalOnly() {
        let model = ApplicationFlowModel()
        let data = SyntheticDocumentFactory.makeImage(type: .idFront, caseId: model.draft.caseId)
        model.attachLocalPhoto(type: .idFront, data: data)

        let document = model.draft.documents.first { $0.type == .idFront }
        XCTAssertNotNil(document)
        XCTAssertEqual(document?.isSynthetic, false)
        XCTAssertEqual(document?.isUploaded, false)
        XCTAssertNotNil(document.flatMap(LocalAttachmentStore.loadImage(for:)))
        XCTAssertEqual(YouthPresentation.attachmentStatusText(for: document), "本機照片（僅存本機、尚未上傳）")
    }

    func testSyntheticLinkPayloadUsesFilledAppFieldsWithoutPhotoOrIDNumber() throws {
        let model = ApplicationFlowModel()
        model.fillTestApplication()
        let data = try SyntheticLinkClient.payload(for: model.draft)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let applicant = try XCTUnwrap(payload["applicant"] as? [String: Any])
        let purchase = try XCTUnwrap(payload["purchase"] as? [String: Any])
        XCTAssertEqual(applicant["fullName"] as? String, model.draft.applicant.fullName)
        XCTAssertEqual(purchase["toolName"] as? String, model.draft.purchase.toolName)
        XCTAssertEqual((purchase["charges"] as? [[String: Any]])?.first?["twdAmount"] as? String, "640")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("TEST-ID-ONLY"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("localRelativePath"))
    }

    func testMobileSubmissionPayloadContainsEnteredFieldsAndActualAttachmentBytes() throws {
        let model = ApplicationFlowModel()
        model.fillTestApplication()
        model.draft.applicant.fullName = "測試申請人乙"
        model.draft.purchase.toolName = "另一項 AI 工具"
        let data = try MobileSubmissionClient.payload(for: model.draft)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let applicant = try XCTUnwrap(payload["applicant"] as? [String: Any])
        let purchase = try XCTUnwrap(payload["purchase"] as? [String: Any])
        let form = try XCTUnwrap(payload["form"] as? [String: Any])
        let documents = try XCTUnwrap(payload["documents"] as? [[String: Any]])
        XCTAssertEqual(applicant["fullName"] as? String, "測試申請人乙")
        XCTAssertEqual(purchase["toolName"] as? String, "另一項 AI 工具")
        XCTAssertEqual(form["nationalID"] as? String, "TEST-ID-ONLY")
        XCTAssertEqual(documents.count, model.draft.documents.count)
        XCTAssertNotNil(Data(base64Encoded: try XCTUnwrap(documents.first?["base64"] as? String)))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("localRelativePath"))
    }

    func testRemoveDocumentDeletesLocalFile() throws {
        let model = ApplicationFlowModel()
        model.attachSynthetic(.idFront)
        let document = try XCTUnwrap(model.draft.documents.first)
        XCTAssertNotNil(LocalAttachmentStore.loadImage(for: document))
        model.removeDocument(.idFront)
        XCTAssertTrue(model.draft.documents.isEmpty)
        XCTAssertNil(LocalAttachmentStore.loadImage(for: document))
    }

    func testFailedPhotoReplaceKeepsExistingAttachment() throws {
        let model = ApplicationFlowModel()
        let first = SyntheticDocumentFactory.makeImage(type: .idFront, caseId: model.draft.caseId)
        model.attachLocalPhoto(type: .idFront, data: first)
        let original = try XCTUnwrap(model.draft.documents.first)

        LocalAttachmentStore.failNextWrite = true
        model.attachLocalPhoto(type: .idFront, data: first)
        XCTAssertEqual(model.draft.documents.first?.localRelativePath, original.localRelativePath)
        XCTAssertNotNil(LocalAttachmentStore.loadImage(for: original))
        XCTAssertEqual(model.banner, LocalAttachmentError.writeFailed.localizedDescription)
    }

    func testInvalidPhotoDoesNotAttach() {
        let model = ApplicationFlowModel()
        model.attachLocalPhoto(type: .idFront, data: Data([0x00, 0x01]))
        XCTAssertTrue(model.draft.documents.isEmpty)
        XCTAssertEqual(model.banner, LocalAttachmentError.unsupportedFormat.localizedDescription)
    }

    func testStartAndResumeNavigateToApplication() async throws {
        let model = ApplicationFlowModel()
        model.startBlank()
        let firstID = model.draft.caseId
        XCTAssertEqual(model.selectedTab, .application)
        model.draft.applicant.fullName = "合成測試申請人"
        await model.saveDraft()
        let saved = try XCTUnwrap(model.ownCases.first)
        model.startBlank()
        XCTAssertNotEqual(model.draft.caseId, firstID)
        model.resumeDraft(saved)
        XCTAssertEqual(model.draft.applicant.fullName, "合成測試申請人")
        XCTAssertEqual(model.draft.caseId, firstID)
        XCTAssertEqual(model.step, .applicant)
    }

    func testImportPreventsResetAndSave() async {
        let model = ApplicationFlowModel()
        model.draft.applicant.fullName = "保留中的合成資料"
        let id = model.draft.caseId
        model.isImportingAttachment = true
        model.startBlank()
        model.loadTemplate(SyntheticFixtures.generalId)
        await model.saveDraft()
        await model.resetOwnDemoCases()
        XCTAssertEqual(model.draft.caseId, id)
        XCTAssertEqual(model.draft.applicant.fullName, "保留中的合成資料")
        XCTAssertTrue(model.ownCases.isEmpty)
    }

    func testSubmitReplacesDraftAndCannotBeSavedOrSubmittedAgain() async throws {
        let model = ApplicationFlowModel()
        model.loadTemplate(SyntheticFixtures.generalId, attachingSyntheticDocuments: true)
        await model.saveDraft()
        XCTAssertEqual(model.ownCases.count, 1)
        await model.submit()
        XCTAssertNotNil(model.lastSubmittedId)
        let submitted = model.draft
        await model.submit()
        await model.saveDraft()
        XCTAssertEqual(model.draft, submitted)
        XCTAssertEqual(model.ownCases.count, 1)
        XCTAssertEqual(model.ownCases.first?.status, .submitted)
        await model.resetOwnDemoCases()
        XCTAssertTrue(model.ownCases.isEmpty)
        XCTAssertTrue(model.draft.documents.isEmpty)
        XCTAssertNil(model.lastSubmittedId)
    }

    func testSummaryEditingReturnsWithMissingFieldsHighlighted() {
        let model = ApplicationFlowModel()
        model.step = .review
        model.editFromSummary(.purchase)
        XCTAssertEqual(model.step, .purchase)
        XCTAssertTrue(model.isEditingFromSummary)
        model.returnToSummary()
        XCTAssertEqual(model.step, .review)
        XCTAssertFalse(model.issues.isEmpty)
        XCTAssertFalse(model.isEditingFromSummary)
    }

    func testOneTapTestDataCompletesFieldsAndAttachmentsWithoutSubmitting() {
        let model = ApplicationFlowModel()
        model.fillTestApplication()
        XCTAssertEqual(model.selectedTab, .application)
        XCTAssertEqual(model.step, .applicant)
        XCTAssertEqual(model.draft.status, .draft)
        XCTAssertNil(model.lastSubmittedId)
        XCTAssertTrue(model.ownCases.isEmpty)
        XCTAssertTrue(FormValidator.issues(for: model.draft).isEmpty)
        XCTAssertFalse(model.draft.documents.isEmpty)
        XCTAssertTrue(model.draft.documents.allSatisfy { $0.isSynthetic && !$0.isUploaded && LocalAttachmentStore.loadImage(for: $0) != nil })
    }

    func testUnsavedRemovalDoesNotDestroySavedDraftAttachment() async throws {
        let model = ApplicationFlowModel()
        model.startBlank()
        model.attachSynthetic(.idFront)
        await model.saveDraft()
        let saved = try XCTUnwrap(model.ownCases.first)
        let attachment = try XCTUnwrap(saved.documents.first)
        model.removeDocument(.idFront)
        XCTAssertNotNil(LocalAttachmentStore.loadImage(for: attachment))
        model.startBlank()
        model.resumeDraft(saved)
        XCTAssertEqual(model.draft.documents.first, attachment)
    }
}
