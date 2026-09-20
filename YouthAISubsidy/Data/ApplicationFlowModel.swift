import Foundation
import SwiftUI

enum AppTab: Hashable {
    case home, application, cases, about
}

@MainActor
@Observable
final class ApplicationFlowModel {
    var selectedTab: AppTab = .home
    var isImportingAttachment = false
    var draft: SubsidyCase
    var step: WizardStep = .applicant
    var issues: [ValidationIssue] = []
    var cases: [SubsidyCase] = []
    var selectedCase: SubsidyCase?
    var isBusy = false
    var banner: String?
    var lastSubmittedId: String?
    var isEditingFromSummary = false
    var spreadsheetBatchSubmittedCount = 0
    var isSubmittingSpreadsheetBatch = false
    private let repository: any CaseRepository

    func editFromSummary(_ target: WizardStep) {
        guard lastSubmittedId == nil, !isBusy, !isImportingAttachment else { return }
        isEditingFromSummary = true
        issues = []
        step = target
    }

    func returnToSummary() {
        guard !isBusy, !isImportingAttachment else { return }
        step = .review
        isEditingFromSummary = false
        issues = FormValidator.issues(for: draft)
    }

    init(draft: SubsidyCase = .blank(), repository: any CaseRepository = CaseRepositoryFactory.make()) {
        self.draft = draft
        self.repository = repository
    }

    var estimate: SubsidyEstimate {
        SubsidyEstimator.estimate(for: draft)
    }

    var isDemoMode: Bool {
        AppEnvironment.isDemoMode
    }

    var ownCases: [SubsidyCase] {
        YouthPresentation.ownCases(from: cases)
    }

    func refreshCases() async {
        isBusy = true
        defer { isBusy = false }
        do {
            cases = try await repository.listCases()
        } catch {
            banner = error.localizedDescription
        }
    }

    func startBlank() {
        guard !isBusy, !isImportingAttachment else { return }
        clearDraftAttachments()
        draft = .blank(caseId: "DRAFT-LOCAL-\(UUID().uuidString)")
        step = .applicant
        isEditingFromSummary = false
        issues = []
        lastSubmittedId = nil
        banner = nil
        selectedTab = .application
    }

    func loadTemplate(_ id: String, attachingSyntheticDocuments: Bool = false) {
        guard !isBusy, !isImportingAttachment else { return }
        clearDraftAttachments()
        draft = SyntheticFixtures.template(id: id)
        draft.status = .draft
        draft.caseId = "DRAFT-\(id)-\(UUID().uuidString)"
        if attachingSyntheticDocuments {
            attachAllRequiredSyntheticDocuments()
        }
        step = .applicant
        isEditingFromSummary = false
        issues = []
        lastSubmittedId = nil
        banner = "已載入合成測試資料，請逐頁核對；尚未送出。"
        selectedTab = .application
    }

    func fillTestApplication() {
        guard !isBusy, !isImportingAttachment else { return }
        loadTemplate(SyntheticFixtures.generalId, attachingSyntheticDocuments: true)
        banner = "已填入合成測試資料及附件，請按下一步；尚未送出。"
    }

    func resumeDraft(_ item: SubsidyCase) {
        guard item.status == .draft, !isBusy, !isImportingAttachment else { return }
        clearDraftAttachments()
        draft = item
        step = .applicant
        isEditingFromSummary = false
        issues = []
        lastSubmittedId = nil
        banner = "已開啟儲存的草稿，可以繼續填寫。"
        selectedTab = .application
    }

    func attachAllRequiredSyntheticDocuments() {
        let types = FormValidator.requiredDocumentTypes(for: draft)
        for type in types where !draft.documents.contains(where: { $0.type == type }) {
            attachSynthetic(type)
        }
    }

    func attachSynthetic(_ type: DocumentType) {
        let data = SyntheticDocumentFactory.makeImage(type: type, caseId: draft.caseId)
        attachLocalFile(type: type, data: data, isSynthetic: true)
    }

    func attachLocalPhoto(type: DocumentType, data: Data) {
        attachLocalFile(type: type, data: data, isSynthetic: false)
    }

    func reportAttachmentFailure() {
        banner = "無法讀取所選影像。"
    }

    func removeDocument(_ type: DocumentType) {
        if let existing = draft.documents.first(where: { $0.type == type }), !isSavedAttachment(existing) {
            LocalAttachmentStore.removeFile(existing)
        }
        draft.documents.removeAll { $0.type == type }
    }

    func validateCurrentStep() -> Bool {
        issues = FormValidator.issues(for: draft, step: step)
        return issues.isEmpty
    }

    func goNext() {
        guard validateCurrentStep() else { return }
        if let next = step.next {
            step = next
        }
    }

    func goBack() {
        issues = []
        if let previous = step.previous {
            step = previous
        }
    }

    func saveDraft() async {
        guard !isBusy, !isImportingAttachment, lastSubmittedId == nil, draft.status == .draft else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            draft = try await repository.saveDraft(draft)
            banner = "已儲存草稿與附件在這支手機，尚未送出。"
            await refreshCases()
        } catch {
            banner = error.localizedDescription
        }
    }

    func submit() async {
        guard !isBusy, !isImportingAttachment, lastSubmittedId == nil, draft.status == .draft else { return }
        issues = FormValidator.issues(for: draft)
        guard issues.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await repository.submit(draft)
            if result.status.isTerminalDecision {
                banner = "後端回傳了人工審查結果。App 沒有自行核准或駁回。"
            } else if repository is DemoCaseStore {
                banner = "已在這支手機記錄申請；尚未送交市府，附件仍僅存手機。"
            } else {
                banner = "試算表收件服務已收妥這筆申請與附件；不是市府正式收件。"
            }
            draft = result
            lastSubmittedId = result.caseId
            selectedCase = result
            await refreshCases()
        } catch {
            banner = error.localizedDescription
        }
    }

    func openCase(_ item: SubsidyCase) {
        selectedCase = item
    }

    func resetOwnDemoCases() async {
        guard !isBusy, !isImportingAttachment, !isSubmittingSpreadsheetBatch else { return }
        DemoCaseStore.shared.resetOwnCases()
        LocalAttachmentStore.removeAll()
        draft = .blank()
        step = .applicant
        issues = []
        lastSubmittedId = nil
        selectedCase = nil
        await refreshCases()
        banner = "已清除這支手機的申請資料。"
    }

    func loadSpreadsheetBatchProgress() {
        spreadsheetBatchSubmittedCount = SyntheticLoadTest.submittedIds().count
    }

    /// 把 Excel 第 1–20 筆合成案件經收件契約寫入試算表。未連接時不會假裝已送出。
    func submitSpreadsheetBatch() async {
        guard !isSubmittingSpreadsheetBatch, !isBusy, !isImportingAttachment else { return }
        loadSpreadsheetBatchProgress()
        guard repository.writesToSpreadsheet else {
            banner = repository is UnconfiguredSubmissionRepository
                ? "收件憑證尚未設定，這 20 筆沒有寫入試算表。"
                : "尚未連接試算表收件服務，這 20 筆沒有寫入試算表。"
            return
        }
        let batch = SyntheticLoadTest.nextBatch()
        guard !batch.isEmpty else {
            banner = "Excel 第 1–20 筆已送過試算表，不會新增第二筆。"
            return
        }
        isSubmittingSpreadsheetBatch = true
        defer { isSubmittingSpreadsheetBatch = false }
        var sent = 0
        do {
            for prepared in batch {
                var item = prepared.item
                try SyntheticLoadTest.attachDocuments(to: &item, variant: prepared.variant)
                _ = try await repository.submit(item)
                SyntheticLoadTest.markSubmitted(item.caseId)
                sent += 1
                spreadsheetBatchSubmittedCount = SyntheticLoadTest.submittedIds().count
                banner = "已送出 \(spreadsheetBatchSubmittedCount) / \(SyntheticLoadTest.importCap) 筆到試算表。"
            }
            await refreshCases()
            banner = "試算表已收妥 \(spreadsheetBatchSubmittedCount) 筆合成申請與附件；App 沒有自行核准或駁回。"
        } catch {
            await refreshCases()
            banner = sent == 0
                ? error.localizedDescription
                : "已送出 \(spreadsheetBatchSubmittedCount) 筆後中斷：\(error.localizedDescription) 尚未寫入的不會假裝成功。"
        }
    }

    private func attachLocalFile(type: DocumentType, data: Data, isSynthetic: Bool) {
        do {
            let old = draft.documents.first { $0.type == type }
            let document = try LocalAttachmentStore.save(
                data: data,
                type: type,
                caseId: draft.caseId,
                isSynthetic: isSynthetic,
                replacing: []
            )
            if let old, !isSavedAttachment(old) { LocalAttachmentStore.removeFile(old) }
            draft.documents.removeAll { $0.type == type }
            draft.documents.append(document)
            banner = isSynthetic
                ? "已附合成檔（僅存本機、尚未上傳）。"
                : "已將所選影像存在本機，尚未上傳。"
        } catch {
            banner = error.localizedDescription
        }
    }

    private func clearDraftAttachments() {
        let keep = Set(ownCases.flatMap { $0.documents.map(\.localRelativePath) })
        for document in draft.documents where !keep.contains(document.localRelativePath) {
            LocalAttachmentStore.removeFile(document)
        }
    }

    private func isSavedAttachment(_ document: CaseDocument) -> Bool {
        ownCases.contains { item in item.documents.contains { $0.localRelativePath == document.localRelativePath } }
    }
}
