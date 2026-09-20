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

    func testAboutHasNoApiUrlControl() {
        let app = launchReset()
        app.tabBars.buttons["說明"].tap()
        XCTAssertTrue(labeled(app, contains: "競賽原型").waitForExistence(timeout: 5))
        for _ in 0..<3 {
            XCTAssertFalse(labeled(app, contains: "這不是正式案件").exists)
            XCTAssertFalse(labeled(app, contains: "禁止把它寫進 Git").exists)
            app.swipeUp()
        }
        XCTAssertTrue(labeled(app, contains: "API 網址或金鑰").waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["about.openDemo"].exists)
        XCTAssertFalse(labeled(app, contains: "開發測試").exists)
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
        XCTAssertTrue(app.buttons["awareness.zoom.awareness-1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["awareness.zoom.awareness-2"].waitForExistence(timeout: 3))
        XCTAssertFalse(element(app, "awareness.placeholder.awareness-2").exists)
        advance(app)

        XCTAssertTrue(app.staticTexts["estimate.unofficial"].waitForExistence(timeout: 6))
        advance(app)
        XCTAssertTrue(
            labeled(app, contains: "申請沒有送出").waitForExistence(timeout: 8)
                || app.staticTexts["review.resultBanner"].waitForExistence(timeout: 2)
                || app.staticTexts["wizard.feedback"].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.staticTexts["review.submittedId"].exists)

        app.tabBars.buttons["案件"].tap()
        XCTAssertTrue(
            app.staticTexts["cases.emptyOwn"].waitForExistence(timeout: 8)
                || labeled(app, contains: "尚無自己的申請").waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "identifier BEGINSWITH 'cases.id.CASE-DEMO-LOCAL'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["cases.id.CASE-DEMO-GENERAL-001"].exists)
        XCTAssertFalse(app.staticTexts["案件時間軸"].exists)
    }

    @MainActor
    func testSingleSubmitDoesNotAskForSecondSyncOrMacURL() {
        let app = launchReset()
        app.buttons["home.startBlank"].tap()
        app.buttons["wizard.fillTest"].tap()
        for _ in 0..<5 { advance(app) }
        XCTAssertTrue(
            labeled(app, contains: "已收妥").waitForExistence(timeout: 25)
                || labeled(app, contains: "尚未送交市府").waitForExistence(timeout: 2)
                || labeled(app, contains: "申請沒有送出").waitForExistence(timeout: 2)
                || app.staticTexts["review.submittedId"].waitForExistence(timeout: 2)
                || app.staticTexts["wizard.feedback"].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.buttons["review.syntheticLink.submit"].exists)
        XCTAssertFalse(app.buttons["review.syntheticLink.refresh"].exists)
        XCTAssertFalse(app.textFields["Mac 測試網址"].exists)
    }

    @MainActor
    func testAwarenessCardOpensZoomableViewer() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-reset", "--ui-test-autoload-general"]
        app.launch()
        for _ in 0..<3 { advance(app) }
        for id in ["awareness-1", "awareness-2"] {
            let card = app.buttons["awareness.zoom.\(id)"]
            XCTAssertTrue(card.waitForExistence(timeout: 6), id)
            card.tap()

            let image = element(app, "awareness.zoom.image")
            XCTAssertTrue(image.waitForExistence(timeout: 5), id)
            let fitWidth = image.frame.width
            image.doubleTap()
            let deadline = Date().addingTimeInterval(3)
            while image.frame.width <= fitWidth * 1.5 && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            XCTAssertGreaterThan(image.frame.width, fitWidth * 1.5, id)

            app.buttons["awareness.zoom.close"].tap()
            XCTAssertTrue(card.waitForExistence(timeout: 5), id)
            XCTAssertFalse(element(app, "awareness.zoom.image").exists, id)
        }
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
        XCTAssertFalse(app.buttons["documents.remove.idFront"].exists)
        XCTAssertEqual(app.buttons["documents.preview.idFront"].value as? String, "尚未附上")
        app.buttons["documents.preview.idFront"].tap()
        XCTAssertTrue(labeled(app, contains: "尚未附上「身分證正面」").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["documents.preview.close"].exists)
        XCTAssertTrue(app.buttons["documents.pickFile.idFront"].exists)
        app.buttons["documents.camera.idFront"].tap()
        XCTAssertTrue(labeled(app, contains: "此裝置無法使用相機").waitForExistence(timeout: 5))
        app.buttons["documents.synthetic.idFront"].tap()
        XCTAssertEqual(app.buttons["documents.preview.idFront"].value as? String, "已附上")
    }

    private func demoBannerExists(in app: XCUIApplication) -> Bool {
        app.staticTexts["demo.banner"].waitForExistence(timeout: 8)
            || app.otherElements["demo.banner"].waitForExistence(timeout: 2)
            || labeled(app, contains: "尚未送市府").waitForExistence(timeout: 2)
            || labeled(app, contains: "送出不會進表").waitForExistence(timeout: 2)
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
