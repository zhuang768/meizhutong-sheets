import Foundation

final class DemoCaseStore: CaseRepository, @unchecked Sendable {
    static let shared = DemoCaseStore()

    private let defaultsKey = "demo.own-cases.v2"
    private let lock = NSLock()

    private var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YouthAISubsidyCases.json")
    }

    private init() {}

    func listCases() async throws -> [SubsidyCase] {
        try ownCases().sorted { $0.caseId < $1.caseId }
    }

    func listDemoFixtures() -> [SubsidyCase] {
        SyntheticFixtures.all
    }

    func loadCase(id: String) async throws -> SubsidyCase {
        if let fixture = SyntheticFixtures.all.first(where: { $0.caseId == id }) {
            return fixture
        }
        guard let found = try ownCases().first(where: { $0.caseId == id }) else {
            throw CaseRepositoryError.missingCase
        }
        return found
    }

    func saveDraft(_ draft: SubsidyCase) async throws -> SubsidyCase {
        var item = draft
        item.status = .draft
        item.precheck = Precheck.localEstimate(for: item)
        appendAudit(&item, action: "draft_saved", note: "本機 Demo 儲存草稿。")
        try upsert(item)
        return item
    }

    func submit(_ draft: SubsidyCase) async throws -> SubsidyCase {
        let issues = FormValidator.issues(for: draft)
        guard issues.isEmpty else {
            throw CaseRepositoryError.remoteFailed(issues.map(\.message).joined(separator: "\n"))
        }
        var item = draft
        if item.caseId.hasPrefix("DRAFT") || SyntheticFixtures.isFixtureCaseId(item.caseId) {
            item.caseId = "CASE-DEMO-LOCAL-\(UUID().uuidString)"
        }
        item.status = .submitted
        item.precheck = Precheck.localEstimate(for: item)
        item.documents = item.documents.map { document in
            var copy = document
            copy.uploadedAt = nil
            return copy
        }
        appendAudit(&item, action: "submitted", note: "本機 Demo 送出，非正式案件。狀態不是核准或駁回。")
        try upsert(item, replacingCaseId: draft.caseId)
        return item
    }

    /// 網路收件成功後才寫入手機的「我的案件」；失敗不可假裝已送件。
    func saveRemoteCase(_ item: SubsidyCase, replacingCaseId: String) throws {
        try upsert(item, replacingCaseId: replacingCaseId)
    }

    func resetOwnCases() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: storageURL)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: "demo.cases.v1")
    }

    func resetToFixtures() {
        resetOwnCases()
    }

    private func ownCases() throws -> [SubsidyCase] {
        lock.lock()
        defer { lock.unlock() }
        return try readCases()
    }

    private func persist(_ cases: [SubsidyCase]) throws {
        let own = cases.filter { !SyntheticFixtures.isFixtureCaseId($0.caseId) }
        let data = try ContractJSON.encoder.encode(own)
        var url = storageURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private func readCases() throws -> [SubsidyCase] {
        if FileManager.default.fileExists(atPath: storageURL.path) {
            let data = try Data(contentsOf: storageURL)
            return try ContractJSON.decoder.decode([SubsidyCase].self, from: data)
                .filter { !SyntheticFixtures.isFixtureCaseId($0.caseId) }
        }
        guard let legacy = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        let decoded = try ContractJSON.decoder.decode([SubsidyCase].self, from: legacy)
        try persist(decoded)
        return decoded.filter { !SyntheticFixtures.isFixtureCaseId($0.caseId) }
    }

    private func upsert(_ item: SubsidyCase, replacingCaseId: String? = nil) throws {
        guard !SyntheticFixtures.isFixtureCaseId(item.caseId) else { return }
        lock.lock()
        defer { lock.unlock() }
        var cases = try readCases()
        cases.removeAll { SyntheticFixtures.isFixtureCaseId($0.caseId) }
        if let replacingCaseId, replacingCaseId != item.caseId {
            cases.removeAll { $0.caseId == replacingCaseId }
        }
        if let index = cases.firstIndex(where: { $0.caseId == item.caseId }) {
            cases[index] = item
        } else {
            cases.append(item)
        }
        try persist(cases)
    }

    private func appendAudit(_ item: inout SubsidyCase, action: String, note: String) {
        item.auditEvents.append(
            AuditEvent(at: Date(), actor: "youth-app-demo", action: action, note: note)
        )
    }
}
