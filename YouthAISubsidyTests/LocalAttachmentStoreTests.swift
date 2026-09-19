import XCTest
import UIKit
import PDFKit
@testable import YouthAISubsidy

final class LocalAttachmentStoreTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("YouthAISubsidy-tests-\(UUID().uuidString)", isDirectory: true)
        LocalAttachmentStore.overrideDirectory = folder
    }

    override func tearDown() {
        LocalAttachmentStore.failNextWrite = false
        LocalAttachmentStore.removeAll()
        LocalAttachmentStore.overrideDirectory = nil
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    func testSavesSelectedImageAsLocalOnlyAttachment() throws {
        let data = SyntheticDocumentFactory.makeImage(type: .idFront, caseId: "DRAFT-LOCAL-TEST")
        let document = try LocalAttachmentStore.save(
            data: data,
            type: .idFront,
            caseId: "DRAFT-LOCAL-TEST",
            isSynthetic: false,
            replacing: []
        )

        XCTAssertFalse(document.isSynthetic)
        XCTAssertFalse(document.isUploaded)
        XCTAssertNil(document.uploadedAt)
        XCTAssertEqual(document.contentType, "image/png")
        XCTAssertGreaterThan(document.byteCount, 0)
        XCTAssertNotNil(LocalAttachmentStore.loadImage(for: document))
        XCTAssertTrue(FileManager.default.fileExists(atPath: LocalAttachmentStore.fileURL(for: document).path))
        XCTAssertEqual(YouthPresentation.attachmentStatusText(for: document), "本機照片（僅存本機、尚未上傳）")
    }

    func testSyntheticOptionIsSeparateAndAlsoNotUploaded() throws {
        let data = SyntheticDocumentFactory.makeImage(type: .idBack, caseId: "DRAFT-LOCAL-TEST")
        let document = try LocalAttachmentStore.save(
            data: data,
            type: .idBack,
            caseId: "DRAFT-LOCAL-TEST",
            isSynthetic: true,
            replacing: []
        )
        XCTAssertTrue(document.isSynthetic)
        XCTAssertFalse(document.isUploaded)
        XCTAssertEqual(YouthPresentation.attachmentStatusText(for: document), "合成檔（僅存本機、尚未上傳）")
    }

    func testFailedReplaceKeepsPreviousFile() throws {
        let original = try LocalAttachmentStore.save(
            data: SyntheticDocumentFactory.makeImage(type: .idFront, caseId: "KEEP"),
            type: .idFront,
            caseId: "KEEP",
            isSynthetic: false,
            replacing: []
        )
        XCTAssertNotNil(LocalAttachmentStore.loadImage(for: original))

        LocalAttachmentStore.failNextWrite = true
        XCTAssertThrowsError(
            try LocalAttachmentStore.save(
                data: SyntheticDocumentFactory.makeImage(type: .idFront, caseId: "NEW"),
                type: .idFront,
                caseId: "NEW",
                isSynthetic: false,
                replacing: [original]
            )
        ) { error in
            XCTAssertEqual(error as? LocalAttachmentError, .writeFailed)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: LocalAttachmentStore.fileURL(for: original).path))
        XCTAssertNotNil(LocalAttachmentStore.loadImage(for: original))
        XCTAssertFalse(original.isUploaded)
    }

    func testInvalidReplacementDoesNotDeleteOriginal() throws {
        let original = try LocalAttachmentStore.save(
            data: SyntheticDocumentFactory.makeImage(type: .paymentProof, caseId: "KEEP"),
            type: .paymentProof,
            caseId: "KEEP",
            isSynthetic: false,
            replacing: []
        )
        XCTAssertThrowsError(
            try LocalAttachmentStore.save(
                data: Data([0x00, 0x01, 0x02]),
                type: .paymentProof,
                caseId: "KEEP",
                isSynthetic: false,
                replacing: [original]
            )
        )
        XCTAssertThrowsError(
            try LocalAttachmentStore.save(
                data: Data(repeating: 0, count: LocalAttachmentStore.maxBytes + 1),
                type: .paymentProof,
                caseId: "KEEP",
                isSynthetic: false,
                replacing: [original]
            )
        )
        XCTAssertNotNil(LocalAttachmentStore.loadImage(for: original))
    }

    func testReplacingAttachmentRemovesPreviousFile() throws {
        let first = try LocalAttachmentStore.save(
            data: SyntheticDocumentFactory.makeImage(type: .officialReceipt, caseId: "A"),
            type: .officialReceipt,
            caseId: "A",
            isSynthetic: true,
            replacing: []
        )
        let second = try LocalAttachmentStore.save(
            data: SyntheticDocumentFactory.makeImage(type: .officialReceipt, caseId: "B"),
            type: .officialReceipt,
            caseId: "B",
            isSynthetic: false,
            replacing: [first]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: LocalAttachmentStore.fileURL(for: first).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: LocalAttachmentStore.fileURL(for: second).path))
        XCTAssertFalse(second.isUploaded)
    }

    func testRemoveDeletesLocalFile() throws {
        let document = try LocalAttachmentStore.save(
            data: SyntheticDocumentFactory.makeImage(type: .passbookCover, caseId: "A"),
            type: .passbookCover,
            caseId: "A",
            isSynthetic: true,
            replacing: []
        )
        LocalAttachmentStore.removeFile(document)
        XCTAssertNil(LocalAttachmentStore.loadImage(for: document))
        XCTAssertFalse(FileManager.default.fileExists(atPath: LocalAttachmentStore.fileURL(for: document).path))
    }

    func testRejectsEmptyUnsupportedAndOversizedData() {
        XCTAssertThrowsError(try LocalAttachmentStore.save(data: Data(), type: .idFront, caseId: "A", isSynthetic: false, replacing: [])) { error in
            XCTAssertEqual(error as? LocalAttachmentError, .emptyFile)
        }
        XCTAssertThrowsError(try LocalAttachmentStore.save(data: Data([0x00, 0x01, 0x02]), type: .idFront, caseId: "A", isSynthetic: false, replacing: [])) { error in
            XCTAssertEqual(error as? LocalAttachmentError, .unsupportedFormat)
        }
        let oversized = Data(repeating: 0, count: LocalAttachmentStore.maxBytes + 1)
        XCTAssertThrowsError(try LocalAttachmentStore.save(data: oversized, type: .idFront, caseId: "A", isSynthetic: false, replacing: [])) { error in
            XCTAssertEqual(error as? LocalAttachmentError, .tooLarge)
        }
    }

    func testDecodedLegacyUploadedAtIsNotTreatedAsUploaded() throws {
        let json = """
        {"attachedAt":"2026-09-01","byteCount":12,"contentType":"image/png","fileName":"idFront.png","id":"1","isSynthetic":false,"localRelativePath":"idFront.png","type":"idFront","uploadedAt":"2026-09-01"}
        """.data(using: .utf8)!
        let document = try ContractJSON.decoder.decode(CaseDocument.self, from: json)
        XCTAssertFalse(document.isUploaded)
        XCTAssertNil(document.uploadedAt)
    }

    func testPDFIsStoredWithoutChangingBytes() throws {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).pdfData { context in
            context.beginPage()
            ("SYNTHETIC RECEIPT" as NSString).draw(at: CGPoint(x: 10, y: 10), withAttributes: nil)
        }
        let document = try LocalAttachmentStore.save(data: data, type: .officialReceipt, caseId: "PDF-TEST", isSynthetic: false, replacing: [])
        XCTAssertEqual(document.contentType, "application/pdf")
        XCTAssertEqual(try Data(contentsOf: LocalAttachmentStore.fileURL(for: document)), data)
        XCTAssertEqual(PDFDocument(url: LocalAttachmentStore.fileURL(for: document))?.pageCount, 1)
        XCTAssertFalse(document.isUploaded)
        XCTAssertEqual(LocalAttachmentStore.maxBytes, 10_000_000)
    }
}
