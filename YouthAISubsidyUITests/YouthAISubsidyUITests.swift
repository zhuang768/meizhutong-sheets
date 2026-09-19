import XCTest

final class YouthAISubsidyUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testHomeKeepsDemoCasesOutOfOwnList() {
        let app = launchReset()
        XCTAssertTrue(labeled(app, contains: "競賽原型").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["home.startBlank"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["home.openDemo"].exists)
        XCTAssertFalse(app.buttons["home.fillTest"].exists)
        XCTAssertFalse(app.buttons["home.loadGeneral"].exists)
        XCTAssertFalse(app.buttons["home.loadSpecial"].exists)

        app.tabBars.buttons["案件"].tap()
        XCTAssertTrue(app.staticTexts["cases.emptyOwn"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["cases.id.CASE-DEMO-GENERAL-001"].exists)
        XCTAssertFalse(app.staticTexts["cases.id.CASE-DEMO-SPECIAL-002"].exists)
        XCTAssertFalse(app.staticTexts["cases.id.CASE-DEMO-PROXY-003"].exists)
        XCTAssertFalse(app.staticTexts["案件時間軸"].exists)
    }

    func testDemoEntryShowsFixturesAndSupplementHintWithoutAuditTrail() {
        let app = launchReset()
        app.tabBars.buttons["說明"].tap()
        let demo = app.buttons["about.openDemo"]
        for _ in 0..<8 where !demo.isHittable { app.swipeUp() }
        demo.tap()
        XCTAssertTrue(labeled(app, contains: "三筆驗收案例不會出現").waitForExistence(timeout: 5))
        app.buttons["demo.fixture.CASE-DEMO-SPECIAL-002"].tap()
        XCTAssertTrue(
            labeled(app, contains: "不是你的申請").waitForExistence(timeout: 6)
                || element(app, "status.demoFixture").waitForExistence(timeout: 2)
        )
        XCTAssertTrue(labeled(app, contains: "合成補件示範").waitForExistence(timeout: 5))
        XCTAssertTrue(labeled(app, contains: "官方收據未見軟體公司名稱").waitForExistence(timeout: 3))
        XCTAssertTrue(labeled(app, contains: "非正式承辦通知").exists)
        XCTAssertFalse(app.staticTexts["案件時間軸"].exists)
        XCTAssertFalse(labeled(app, contains: "youth-app-demo").exists)
        XCTAssertFalse(labeled(app, contains: "backend-demo").exists)
    }

    func testAboutHasNoApiUrlControl() {
        let app = launchReset()
        app.tabBars.buttons["說明"].tap()
        XCTAssertTrue(labeled(app, contains: "不是正式案件").waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(labeled(app, contains: "GPT").waitForExistence(timeout: 3))
        XCTAssertTrue(labeled(app, contains: "待對齊").exists)
        XCTAssertFalse(app.textFields["settings.apiBaseURL"].exists)
        XCTAssertFalse(app.buttons["settings.save"].exists)
        XCTAssertFalse(app.textFields.containing(NSPredicate(format: "placeholderValue CONTAINS 'http'")).firstMatch.exists)
    }

    func testBlankApplicationShowsValidationErrors() {
        let app = launchReset()
        app.buttons["home.startBlank"].tap()
        XCTAssertTrue(app.buttons["wizard.primary"].waitForExistence(timeout: 5))
        advance(app)
        XCTAssertTrue(labeled(app, contains: "尚未填齊").waitForExistence(timeout: 6))
        XCTAssertTrue(labeled(app, contains: "請填寫申請人姓名").waitForExistence(timeout: 2))
    }

    func testSyntheticDocumentScansRequireReviewBeforeFilling() {
        let app = launchReset()
        app.buttons["home.startBlank"].tap()
        let scanID = app.buttons["applicant.scanSyntheticID"]
        XCTAssertTrue(scanID.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["applicant.camera.idFront"].exists)
        XCTAssertTrue(app.buttons["applicant.album.idFront"].exists)
        scanID.tap()
        XCTAssertTrue(app.buttons["scan.confirmApply"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.textFields["applicant.fullName"].value as? String, "申請人姓名")
        app.buttons["scan.confirmApply"].tap()
        XCTAssertEqual(app.textFields["applicant.fullName"].value as? String, "合成林青禾")

        app.buttons["wizard.fillTest"].tap()
        advance(app)
        let scanReceipt = app.buttons["purchase.scanSyntheticReceipt"]
        XCTAssertTrue(scanReceipt.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["purchase.cameraReceipt"].exists)
        XCTAssertTrue(app.buttons["purchase.albumReceipt"].exists)
        scanReceipt.tap()
        XCTAssertTrue(app.buttons["scan.confirmApply"].waitForExistence(timeout: 15))
        app.buttons["scan.confirmApply"].tap()
        XCTAssertEqual(app.textFields["purchase.toolName"].value as? String, "Cursor")
    }

    func testDemoApplicationFlow() throws {
        let app = launchReset()
        app.buttons["home.startBlank"].tap()
        let fill = app.buttons["wizard.fillTest"]
        XCTAssertTrue(fill.waitForExistence(timeout: 5))
        fill.tap()

        XCTAssertTrue(demoBannerExists(in: app))

        XCTAssertTrue(app.buttons["wizard.primary"].waitForExistence(timeout: 5))

        advance(app)
        advance(app)
        if app.buttons["documents.attachAllSynthetic"].waitForExistence(timeout: 3) {
            app.buttons["documents.attachAllSynthetic"].tap()
        }
        XCTAssertTrue(labeled(app, contains: "僅存本機、尚未上傳").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["documents.pickAlbum.idFront"].exists)
        XCTAssertTrue(app.buttons["documents.synthetic.idFront"].exists)
        advance(app)

        XCTAssertTrue(labeled(app, contains: "不是政府公告").waitForExistence(timeout: 6))
        XCTAssertTrue(labeled(app, contains: "待設計師提供").waitForExistence(timeout: 3))
        advance(app)

        XCTAssertTrue(app.staticTexts["estimate.unofficial"].waitForExistence(timeout: 6))
        advance(app)
        XCTAssertTrue(
            app.staticTexts["review.submittedId"].waitForExistence(timeout: 8)
                || labeled(app, contains: "已記錄送出").waitForExistence(timeout: 3)
                || labeled(app, contains: "案件編號").waitForExistence(timeout: 2)
                || labeled(app, contains: "CASE-DEMO-LOCAL").waitForExistence(timeout: 2)
                || app.staticTexts["review.resultBanner"].waitForExistence(timeout: 2)
        )

        app.tabBars.buttons["案件"].tap()
        let submitted = app.staticTexts.containing(NSPredicate(format: "identifier BEGINSWITH 'cases.id.CASE-DEMO-LOCAL'")).firstMatch
        XCTAssertTrue(submitted.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["cases.id.CASE-DEMO-GENERAL-001"].exists)

        submitted.tap()
        XCTAssertTrue(element(app, "status.caseId").waitForExistence(timeout: 5) || labeled(app, contains: "CASE-DEMO-LOCAL").waitForExistence(timeout: 2))
        XCTAssertTrue(labeled(app, contains: "目前沒有承辦發出的補件通知").waitForExistence(timeout: 3))
        XCTAssertFalse(labeled(app, contains: "官方收據未見軟體公司名稱").exists)
        XCTAssertFalse(app.staticTexts["案件時間軸"].exists)
        XCTAssertFalse(labeled(app, contains: "不是你的申請").exists)
    }

    @MainActor
    func testSingleSubmitDoesNotAskForSecondSyncOrMacURL() {
        let app = launchReset()
        app.buttons["home.startBlank"].tap()
        app.buttons["wizard.fillTest"].tap()
        for _ in 0..<5 { advance(app) }
        XCTAssertTrue(app.staticTexts["review.submittedId"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["review.syntheticLink.submit"].exists)
        XCTAssertFalse(app.buttons["review.syntheticLink.refresh"].exists)
        XCTAssertFalse(app.textFields["Mac 測試網址"].exists)
    }

    private func launchReset() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-reset"]
        app.launch()
        return app
    }

    func testDraftCanBeSavedAndResumed() {
        let app = launchReset()
        app.buttons["home.startBlank"].tap()
        XCTAssertTrue(app.buttons["wizard.saveDraft"].waitForExistence(timeout: 5))
        app.buttons["wizard.saveDraft"].tap()
        XCTAssertTrue(labeled(app, contains: "已儲存草稿").waitForExistence(timeout: 5))
        app.tabBars.buttons["案件"].tap()
        let draft = app.staticTexts.containing(NSPredicate(format: "identifier BEGINSWITH 'cases.id.DRAFT'")).firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap()
        XCTAssertTrue(app.buttons["status.resumeDraft"].waitForExistence(timeout: 5))
        app.buttons["status.resumeDraft"].tap()
        XCTAssertTrue(app.buttons["wizard.saveDraft"].waitForExistence(timeout: 5))
        XCTAssertTrue(labeled(app, contains: "已開啟儲存的草稿").exists)
    }

    func testDocumentPreviewCloseRemoveAndCameraFeedback() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-reset", "--ui-test-autoload-general"]
        app.launch()
        advance(app)
        advance(app)
        let preview = app.buttons["documents.preview.idFront"]
        for _ in 0..<10 {
            if preview.exists && preview.isHittable && preview.frame.midY < app.frame.height - 190 && preview.frame.midY > 280 { break }
            let list = app.collectionViews.firstMatch
            let scrollDown = preview.exists && preview.frame.midY < 280
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: scrollDown ? 0.4 : 0.65))
                .press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: scrollDown ? 0.65 : 0.4)))
        }
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        XCTAssertTrue(app.buttons["documents.preview.close"].waitForExistence(timeout: 5))
        app.buttons["documents.preview.close"].tap()
        app.buttons["documents.remove.idFront"].tap()
        XCTAssertFalse(app.buttons["documents.preview.idFront"].exists)
        XCTAssertTrue(app.buttons["documents.pickFile.idFront"].exists)
        app.buttons["documents.camera.idFront"].tap()
        XCTAssertTrue(labeled(app, contains: "此裝置無法使用相機").waitForExistence(timeout: 5))
        app.buttons["documents.synthetic.idFront"].tap()
        XCTAssertTrue(app.buttons["documents.preview.idFront"].exists)
    }

    private func demoBannerExists(in app: XCUIApplication) -> Bool {
        app.staticTexts["demo.banner"].waitForExistence(timeout: 8)
            || app.otherElements["demo.banner"].waitForExistence(timeout: 2)
            || labeled(app, contains: "尚未送市府").waitForExistence(timeout: 2)
    }

    private func labeled(_ app: XCUIApplication, contains text: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func advance(_ app: XCUIApplication) {
        if app.buttons["keyboard.dismiss"].exists {
            app.buttons["keyboard.dismiss"].tap()
        }
        app.buttons["wizard.primary"].tap()
    }
}
