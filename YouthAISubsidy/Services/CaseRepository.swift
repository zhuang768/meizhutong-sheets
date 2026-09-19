import Foundation

protocol CaseRepository: Sendable {
    func listCases() async throws -> [SubsidyCase]
    func loadCase(id: String) async throws -> SubsidyCase
    func saveDraft(_ draft: SubsidyCase) async throws -> SubsidyCase
    func submit(_ draft: SubsidyCase) async throws -> SubsidyCase
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
        guard AppEnvironment.isRemoteAPIEnabled, let url = AppEnvironment.configuredBaseURL else {
            return DemoCaseStore.shared
        }
        return MobileCaseRepository(baseURL: url)
    }
}
