import Foundation

/// Provisional teammate API client. Paths are not an official contract.
/// This client only sends JSON metadata. It never uploads local photo bytes,
/// and it must not receive a GPT / OpenAI API key.
struct TeamAPIClient: CaseRepository {
    var baseURL: URL
    var session: URLSession = .shared

    func listCases() async throws -> [SubsidyCase] {
        try await get(path: "v1/cases")
    }

    func loadCase(id: String) async throws -> SubsidyCase {
        try await get(path: "v1/cases/\(id)")
    }

    func saveDraft(_ draft: SubsidyCase) async throws -> SubsidyCase {
        try await send(path: "v1/cases/\(draft.caseId)", method: "PATCH", body: draft)
    }

    func submit(_ draft: SubsidyCase) async throws -> SubsidyCase {
        let submitted: SubsidyCase = try await send(
            path: "v1/cases/\(draft.caseId)/submit",
            method: "POST",
            body: draft
        )
        if submitted.status.isTerminalDecision && draft.status != submitted.status {
            // Accept only if backend assigned it; the App never sets these locally.
        }
        return submitted
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        try rejectIfDisabled()
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await decode(request)
    }

    private func send<T: Decodable, B: Encodable>(path: String, method: String, body: B) async throws -> T {
        try rejectIfDisabled()
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try ContractJSON.encoder.encode(body)
        return try await decode(request)
    }

    private func rejectIfDisabled() throws {
        guard AppEnvironment.isRemoteAPIEnabled else {
            throw CaseRepositoryError.remoteFailed("隊友 API 契約未確認，本版本僅在這支手機儲存，不會送出網路請求。")
        }
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CaseRepositoryError.remoteFailed("團隊 API 沒有回傳 HTTP 回應。")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw CaseRepositoryError.remoteFailed("團隊 API 回應 \(http.statusCode)。契約未定前請使用手機內儲存。")
            }
            return try ContractJSON.decoder.decode(T.self, from: data)
        } catch let error as CaseRepositoryError {
            throw error
        } catch {
            throw CaseRepositoryError.remoteFailed("無法連線團隊 API：\(error.localizedDescription)")
        }
    }
}
