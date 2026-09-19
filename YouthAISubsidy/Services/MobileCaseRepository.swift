import Foundation
import Security

/// 手機只保存自己的案件憑證；查詢代碼不提供給其他人的裝置。
enum MobileCaseTokenStore {
    private static let service = "com.meizhuhackathon.YouthAISubsidy.case-access"

    static func save(_ token: String, for caseId: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: caseId,
        ]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw CaseRepositoryError.remoteFailed("案件已送達後端，但手機無法安全保存查詢憑證；請記下案件編號。")
        }
    }

    static func load(for caseId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: caseId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// 草稿留在手機；只在後端回覆收件成功後才更新「我的案件」。
struct MobileCaseRepository: CaseRepository {
    let baseURL: URL

    func listCases() async throws -> [SubsidyCase] {
        let local = try await DemoCaseStore.shared.listCases()
        var updated: [SubsidyCase] = []
        for var item in local {
            if item.status != .draft && MobileCaseTokenStore.load(for: item.caseId) == nil {
                // 舊版僅存手機的案件不可冒充成雲端已收件案件。
                continue
            }
            if item.status != .draft, let token = MobileCaseTokenStore.load(for: item.caseId),
               let status = try? await MobileSubmissionClient.status(caseId: item.caseId, accessToken: token, baseURL: baseURL) {
                item.status = status.status
                item.publicStatusNote = status.statusNote
                try? DemoCaseStore.shared.saveRemoteCase(item, replacingCaseId: item.caseId)
            }
            updated.append(item)
        }
        return updated
    }

    func loadCase(id: String) async throws -> SubsidyCase {
        guard let item = try await listCases().first(where: { $0.caseId == id }) else {
            throw CaseRepositoryError.missingCase
        }
        return item
    }

    func saveDraft(_ draft: SubsidyCase) async throws -> SubsidyCase {
        try await DemoCaseStore.shared.saveDraft(draft)
    }

    func submit(_ draft: SubsidyCase) async throws -> SubsidyCase {
        let receipt = try await MobileSubmissionClient.submit(draft, baseURL: baseURL)
        var received = draft
        received.caseId = receipt.case.caseId
        received.status = receipt.case.status
        received.documents = received.documents.map { document in
            var copy = document
            copy.uploadedAt = Date()
            return copy
        }
        try MobileCaseTokenStore.save(receipt.accessToken, for: received.caseId)
        try DemoCaseStore.shared.saveRemoteCase(received, replacingCaseId: draft.caseId)
        return received
    }
}
