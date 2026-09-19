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
        XCTAssertFalse(AppEnvironment.isRemoteAPIEnabled)
        XCTAssertTrue(AppEnvironment.isDemoMode)
        XCTAssertEqual(
            AppEnvironment.connectionLabel,
            "尚未連接市府申辦系統；資料只保存在這支手機，非正式案件。"
        )
        XCTAssertTrue(CaseRepositoryFactory.make() is DemoCaseStore)

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

        let repository = CaseRepositoryFactory.make()
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

    func testDisabledTeamAPIClientDoesNotSend() async {
        let client = TeamAPIClient(baseURL: URL(string: "https://stale.example.test")!)
        do {
            _ = try await client.listCases()
            XCTFail("Disabled client should not succeed")
        } catch {
            XCTAssertEqual(NetworkHitProbe.requestCount, 0)
            XCTAssertTrue(error.localizedDescription.contains("不會送出網路請求"))
        }
    }

    func testDiscardRemovesLegacyBaseURL() {
        XCTAssertNil(AppEnvironment.configuredBaseURL, "手機舊設定不能啟用網路送件")
        AppEnvironment.discardStaleConnectionSettings()
        XCTAssertNil(UserDefaults.standard.string(forKey: AppEnvironment.apiBaseURLDefaultsKey))
        AppEnvironment.setBaseURLString("https://should-be-ignored.example.test")
        XCTAssertNil(UserDefaults.standard.string(forKey: AppEnvironment.apiBaseURLDefaultsKey))
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

    func testModelDraftSubmitAndRefreshStayLocalWithStaleURL() async throws {
        let model = ApplicationFlowModel(draft: SyntheticFixtures.fillableGeneral())
        model.draft.caseId = "DRAFT-STALE-MODEL"
        model.attachAllRequiredSyntheticDocuments()

        await model.saveDraft()
        XCTAssertTrue(model.banner?.contains("這支手機") == true)
        XCTAssertFalse(model.banner?.contains("已上傳") == true)
        XCTAssertFalse(model.banner?.contains("正式受理") == true)

        await model.submit()
        XCTAssertTrue(model.banner?.contains("這支手機") == true)
        XCTAssertTrue(model.banner?.contains("尚未送交市府") == true)
        XCTAssertFalse(model.banner?.contains("已上傳") == true)
        XCTAssertNotNil(model.lastSubmittedId)

        await model.refreshCases()
        XCTAssertFalse(model.ownCases.isEmpty)
        XCTAssertEqual(NetworkHitProbe.requestCount, 0)
        XCTAssertTrue(model.ownCases.allSatisfy { $0.documents.allSatisfy { !$0.isUploaded } })
    }
}
