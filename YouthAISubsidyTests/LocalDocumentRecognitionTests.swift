import XCTest
import UIKit
@testable import YouthAISubsidy

final class LocalDocumentRecognitionTests: XCTestCase {
    func testParsesOnlyLabeledSyntheticIdentityFields() throws {
        let sample = try LocalDocumentRecognition.parseSynthetic(lines: [
            "SYNTHETIC DOCUMENT - NOT REAL",
            "姓名 Name: 合成林青禾",
            "出生 Birth: 1998/06/15",
            "測試代碼 ID: TEST-ID-ONLY"
        ], type: .idFront)
        XCTAssertEqual(sample.name, "合成林青禾")
        XCTAssertEqual(sample.documentNumber, "TEST-ID-ONLY")
        XCTAssertNotNil(sample.birthDate)
        let reverse = try LocalDocumentRecognition.parseSynthetic(lines: [
            "SYNTHETIC DOCUMENT - NOT REAL",
            "戶籍 Address: 新竹市東區合成路0號",
            "郵遞區號 ZIP: 300"
        ], type: .idBack)
        let combined = LocalDocumentRecognition.combinedSyntheticID(front: sample, back: reverse)
        XCTAssertEqual(combined.postalCode, "300")
        XCTAssertEqual(combined.address, "新竹市東區合成路0號")
    }

    func testParsesOnlyLabeledSyntheticReceiptFields() throws {
        let sample = try LocalDocumentRecognition.parseSynthetic(lines: [
            "SYNTHETIC RECEIPT - NOT REAL",
            "工具 Tool: Cursor", "賣方 Vendor: Anysphere",
            "購買日 Date: 2026/08/01", "金額 Amount: USD 20", "臺幣 TWD: 640"
        ], type: .officialReceipt)
        XCTAssertEqual(sample.toolName, "Cursor")
        XCTAssertEqual(sample.vendorName, "Anysphere")
        XCTAssertEqual(sample.originalAmount, 20)
        XCTAssertEqual(sample.currency, "USD")
        XCTAssertEqual(sample.twdAmount, 640)
    }

    func testRejectsUnmarkedText() {
        XCTAssertThrowsError(try LocalDocumentRecognition.parseSynthetic(
            lines: ["Name: Somebody", "Birth: 1998/06/15"], type: .idFront
        ))
    }

    func testDifferentReceiptLayoutsDoNotGuessMissingProduct() throws {
        let clippedEmail = try LocalDocumentRecognition.parseReceipt(lines: [
            "Receipt from Sample AI Company",
            "NT$600.00",
            "Paid August 12, 2026"
        ])
        XCTAssertEqual(clippedEmail.vendorName, "Sample AI Company")
        XCTAssertNil(clippedEmail.toolName)
        XCTAssertEqual(clippedEmail.twdAmount, 600)
        XCTAssertNotNil(clippedEmail.purchaseDate)

        let itemizedEmail = try LocalDocumentRecognition.parseReceipt(lines: [
            "Nova AI Pro Subscription   NT$3,300.00",
            "Purchase Date: 2026/09/01",
            "Vendor: Example Software"
        ])
        XCTAssertEqual(itemizedEmail.toolName, "Nova AI Pro Subscription")
        XCTAssertEqual(itemizedEmail.vendorName, "Example Software")
        XCTAssertEqual(itemizedEmail.twdAmount, 3300)
    }

    func testReadsTextFromLocalPDFWithoutNetwork() throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800))
        let pdf = renderer.pdfData { context in
            context.beginPage()
            let lines = ["Receipt from Example Software", "Product: Nova AI Pro", "Total: NT$480.00", "Paid August 12, 2026"]
            for (index, line) in lines.enumerated() {
                line.draw(at: CGPoint(x: 48, y: 60 + index * 52), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            }
        }
        let result = try LocalDocumentRecognition.recognizeLocalReceipt(pdf)
        XCTAssertEqual(result.toolName, "Nova AI Pro")
        XCTAssertEqual(result.vendorName, "Example Software")
        XCTAssertEqual(result.twdAmount, 480)
        XCTAssertNotNil(result.purchaseDate)
    }

    func testVisionReadsGeneratedSyntheticImages() throws {
        let id = try LocalDocumentRecognition.recognizeSynthetic(
            SyntheticDocumentFactory.makeImage(type: .idFront, caseId: "DEMO"), type: .idFront
        )
        XCTAssertNotNil(id.documentNumber)
        XCTAssertTrue(id.hasFields)
        let back = try LocalDocumentRecognition.recognizeSynthetic(
            SyntheticDocumentFactory.makeImage(type: .idBack, caseId: "DEMO"), type: .idBack
        )
        XCTAssertEqual(back.postalCode, "300")
        let receipt = try LocalDocumentRecognition.recognizeSynthetic(
            SyntheticDocumentFactory.makeImage(type: .officialReceipt, caseId: "DEMO"), type: .officialReceipt
        )
        XCTAssertEqual(receipt.toolName, "Cursor")
        XCTAssertEqual(receipt.currency, "USD")
    }

    func testPhotoReceiptUsesVisionAndKeepsPreviewForReview() throws {
        let photo = SyntheticDocumentFactory.makeImage(type: .officialReceipt, caseId: "PHOTO-TEST")
        let result = try LocalDocumentRecognition.recognizeLocalReceipt(photo)
        XCTAssertEqual(result.toolName, "Cursor")
        XCTAssertEqual(result.currency, "USD")
        XCTAssertEqual(result.imageData, photo)
    }

    func testCameraIdentityRequiresBothClearlyMarkedSyntheticSides() throws {
        let front = SyntheticDocumentFactory.makeImage(type: .idFront, caseId: "CAMERA-TEST")
        let back = SyntheticDocumentFactory.makeImage(type: .idBack, caseId: "CAMERA-TEST")
        let result = try LocalDocumentRecognition.recognizeIdentity(front: front, back: back)
        XCTAssertEqual(result.name, "合成林青禾")
        XCTAssertNotNil(result.reverseImageData)
    }

    func testRealCardTextOnlyFillsExplicitHighConfidenceFields() throws {
        let found = try LocalDocumentRecognition.parseIdentity(
            frontLines: ["中華民國國民身分證", "姓 名：林測試", "出生 民國 88 年 6 月 15 日", "A000000000"],
            backLines: ["住 址：新竹市東區測試路一號"]
        )
        XCTAssertEqual(found.name, "林測試")
        XCTAssertEqual(found.address, "新竹市東區測試路一號")
        XCTAssertNotNil(found.birthDate)
        XCTAssertNil(found.documentNumber, "Invalid checksum must not be auto-filled")
        XCTAssertNil(found.postalCode, "The card does not provide a postal code")
    }

    func testUnrelatedPhotoIsNotAcceptedAsIdentityCard() {
        XCTAssertThrowsError(try LocalDocumentRecognition.parseIdentity(
            frontLines: ["姓名：林測試", "出生 民國 88 年 6 月 15 日"],
            backLines: ["住址：新竹市東區測試路一號"]
        ))
    }
}
