import XCTest
@testable import YouthAISubsidy

final class NetworkHitProbe: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        requestCount += 1
        return false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {}
    override func stopLoading() {}
}

final class AppEnvironmentTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NetworkHitProbe.requestCount = 0
        URLProtocol.registerClass(NetworkHitProbe.self)
        UserDefaults.standard.set("https://stale.example.test/v1", forKey: AppEnvironment.apiBaseURLDefaultsKey)
        DemoCaseStore.shared.resetOwnCases()
    }

    override func tearDown() {
        URLProtocol.unregisterClass(NetworkHitProbe.self)
        NetworkHitProbe.requestCount = 0
        AppEnvironment.discardStaleConnectionSettings()
        DemoCaseStore.shared.resetOwnCases()
        super.tearDown()
    }

    func testStaleBaseURLKeepsLocalDemoAndMakesNoNetworkCalls() async throws {
        XCTAssertNotEqual(AppEnvironment.configuredBaseURL?.host, "stale.example.test")
        XCTAssertTrue(AppEnvironment.connectionLabel(for: .missingCredential).contains("不會寫入試算表"))
        XCTAssertEqual(
            AppEnvironment.connectionLabel(for: .localOnly),
            "尚未連接市府申辦系統；資料只保存在這支手機，非正式案件。"
        )
        XCTAssertTrue(CaseRepositoryFactory.make(baseURL: nil, clientKey: nil) is DemoCaseStore)
        if AppEnvironment.configuredClientKey == nil {
            XCTAssertEqual(AppEnvironment.connectionState, .missingCredential)
            XCTAssertTrue(CaseRepositoryFactory.make() is UnconfiguredSubmissionRepository)
        } else {
            XCTAssertEqual(AppEnvironment.connectionState, .spreadsheetIntake)
            XCTAssertTrue(CaseRepositoryFactory.make() is MobileCaseRepository)
        }

        var draft = SyntheticFixtures.fillableGeneral()
        draft.caseId = "DRAFT-STALE-URL"
        draft.documents = FormValidator.requiredDocumentTypes(for: draft).map { type in
            CaseDocument(
                id: type.rawValue,
                type: type,
                fileName: "\(type.rawValue).png",
                localRelativePath: "\(type.rawValue).png",
                isSynthetic: true
            )
        }

        let repository = CaseRepositoryFactory.make(baseURL: nil, clientKey: nil)
        let saved = try await repository.saveDraft(draft)
        let submitted = try await repository.submit(saved)
        let listed = try await repository.listCases()

        XCTAssertEqual(saved.status, .draft)
        XCTAssertEqual(submitted.status, .submitted)
        XCTAssertTrue(submitted.documents.allSatisfy { !$0.isUploaded })
        XCTAssertTrue(listed.contains(where: { $0.caseId == submitted.caseId }))
        XCTAssertEqual(NetworkHitProbe.requestCount, 0)
        XCTAssertFalse(AppEnvironment.connectionLabel.contains("已上傳"))
        XCTAssertFalse(AppEnvironment.connectionLabel.contains("正式受理"))
    }

    func testDiscardRemovesLegacyBaseURL() {
        XCTAssertNotEqual(AppEnvironment.configuredBaseURL?.host, "stale.example.test", "手機舊設定不能覆蓋建置時網址")
        AppEnvironment.discardStaleConnectionSettings()
        XCTAssertNil(UserDefaults.standard.string(forKey: AppEnvironment.apiBaseURLDefaultsKey))
    }

    func testConfiguredServiceWithoutCredentialNeverSubmitsLocally() async throws {
        let repository = CaseRepositoryFactory.make(
            baseURL: URL(string: "https://example.test/exec"), clientKey: nil
        )
        XCTAssertTrue(repository is UnconfiguredSubmissionRepository)
        XCTAssertTrue(CaseRepositoryFactory.make(
            baseURL: URL(string: "https://example.test/exec"), clientKey: "  "
        ) is UnconfiguredSubmissionRepository)
        XCTAssertTrue(CaseRepositoryFactory.make(baseURL: nil, clientKey: nil) is DemoCaseStore)
        XCTAssertTrue(CaseRepositoryFactory.make(
            baseURL: URL(string: "https://example.test/exec"), clientKey: "test-only"
        ) is MobileCaseRepository)

        var draft = SyntheticFixtures.fillableGeneral()
        draft.caseId = "DRAFT-MISSING-CREDENTIAL"
        let saved = try await repository.saveDraft(draft)
        XCTAssertEqual(saved.status, .draft)
        do {
            _ = try await repository.submit(saved)
            XCTFail("缺少憑證不能回報送件成功")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("申請沒有送出"))
        }
        let cases = try await repository.listCases()
        XCTAssertEqual(cases.first(where: { $0.caseId == saved.caseId })?.status, .draft)
        XCTAssertEqual(NetworkHitProbe.requestCount, 0)
    }
}

@MainActor
final class ApplicationFlowNetworkIsolationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NetworkHitProbe.requestCount = 0
        URLProtocol.registerClass(NetworkHitProbe.self)
        UserDefaults.standard.set("https://stale.example.test/v1", forKey: AppEnvironment.apiBaseURLDefaultsKey)
        DemoCaseStore.shared.resetOwnCases()
    }

    override func tearDown() {
        URLProtocol.unregisterClass(NetworkHitProbe.self)
        NetworkHitProbe.requestCount = 0
        AppEnvironment.discardStaleConnectionSettings()
        DemoCaseStore.shared.resetOwnCases()
        super.tearDown()
    }

    func testModelDoesNotPretendSuccessWithoutCredential() async throws {
        let model = ApplicationFlowModel(
            draft: SyntheticFixtures.fillableGeneral(),
            repository: UnconfiguredSubmissionRepository()
        )
        model.draft.caseId = "DRAFT-STALE-MODEL"
        model.attachAllRequiredSyntheticDocuments()

        await model.saveDraft()
        XCTAssertTrue(model.banner?.contains("這支手機") == true)
        XCTAssertFalse(model.banner?.contains("已上傳") == true)
        XCTAssertFalse(model.banner?.contains("正式受理") == true)

        await model.submit()
        XCTAssertNil(model.lastSubmittedId)
        XCTAssertEqual(model.draft.status, .draft)
        XCTAssertTrue(model.banner?.contains("申請沒有送出") == true)
        XCTAssertFalse(model.banner?.contains("已上傳") == true)
        XCTAssertFalse(model.banner?.contains("尚未送交市府") == true)

        await model.refreshCases()
        XCTAssertEqual(model.ownCases.first(where: { $0.caseId == "DRAFT-STALE-MODEL" })?.status, .draft)
        XCTAssertEqual(NetworkHitProbe.requestCount, 0)
        XCTAssertTrue(model.ownCases.allSatisfy { $0.documents.allSatisfy { !$0.isUploaded } })
    }

    func testModelLocalDemoSubmitDoesNotUseNetwork() async throws {
        let model = ApplicationFlowModel(
            draft: SyntheticFixtures.fillableGeneral(),
            repository: DemoCaseStore.shared
        )
        model.draft.caseId = "DRAFT-LOCAL-DEMO-MODEL"
        model.attachAllRequiredSyntheticDocuments()

        await model.saveDraft()
        await model.submit()
        XCTAssertNotNil(model.lastSubmittedId)
        XCTAssertTrue(model.banner?.contains("這支手機") == true)
        XCTAssertTrue(model.banner?.contains("尚未送交市府") == true)
        XCTAssertEqual(NetworkHitProbe.requestCount, 0)
    }
}
