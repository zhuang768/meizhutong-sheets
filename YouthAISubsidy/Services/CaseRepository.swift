import Foundation

protocol CaseRepository: Sendable {
    var writesToSpreadsheet: Bool { get }
    func listCases() async throws -> [SubsidyCase]
    func loadCase(id: String) async throws -> SubsidyCase
    func saveDraft(_ draft: SubsidyCase) async throws -> SubsidyCase
    func submit(_ draft: SubsidyCase) async throws -> SubsidyCase
}

extension CaseRepository {
    var writesToSpreadsheet: Bool { false }
}

enum CaseRepositoryError: LocalizedError {
    case missingCase
    case remoteFailed(String)
    case cannotDecideLocally

    var errorDescription: String? {
        switch self {
        case .missingCase:
            return "找不到案件。"
        case .remoteFailed(let message):
            return message
        case .cannotDecideLocally:
            return "核准或駁回只能來自後端人工處理，App 不可自行產生。"
        }
    }
}

enum CaseRepositoryFactory {
    static func make() -> any CaseRepository {
        make(baseURL: AppEnvironment.configuredBaseURL, clientKey: AppEnvironment.configuredClientKey)
    }

    static func make(baseURL: URL?, clientKey: String?) -> any CaseRepository {
        guard let url = baseURL else {
            return DemoCaseStore.shared
        }
        let trimmedKey = clientKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedKey.isEmpty else {
            return UnconfiguredSubmissionRepository()
        }
        return MobileCaseRepository(baseURL: url)
    }
}

/// 已指定收件服務卻缺少憑證時，允許離線草稿，但絕不把送件改成手機內成功。
struct UnconfiguredSubmissionRepository: CaseRepository {
    func listCases() async throws -> [SubsidyCase] {
        try await DemoCaseStore.shared.listCases()
    }

    func loadCase(id: String) async throws -> SubsidyCase {
        try await DemoCaseStore.shared.loadCase(id: id)
    }

    func saveDraft(_ draft: SubsidyCase) async throws -> SubsidyCase {
        try await DemoCaseStore.shared.saveDraft(draft)
    }

    func submit(_ draft: SubsidyCase) async throws -> SubsidyCase {
        throw CaseRepositoryError.remoteFailed("試算表收件服務尚未完成憑證設定；申請沒有送出，請先儲存草稿。")
    }
}
