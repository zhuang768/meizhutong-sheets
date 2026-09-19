import Foundation
import UIKit
import PDFKit

enum LocalAttachmentError: LocalizedError, Equatable {
    case unsupportedFormat
    case tooLarge
    case emptyFile
    case writeFailed
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "請選擇可開啟的 JPEG、PNG、HEIC 影像或 PDF；本機支援格式不代表市府已核可。"
        case .tooLarge:
            return "檔案超過 10 MB 上限，請選擇較小的檔案。"
        case .emptyFile:
            return "所選影像是空的，沒有寫入本機。"
        case .writeFailed:
            return "無法把影像寫入本機。"
        case .unreadable:
            return "無法讀取所選影像。"
        }
    }
}

enum DetectedImageFormat: String {
    case jpeg
    case png
    case heic

    var contentType: String {
        switch self {
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        case .heic: return "image/heic"
        }
    }

    var fileExtension: String {
        rawValue
    }

    static func detect(_ data: Data) -> DetectedImageFormat? {
        guard data.count >= 12 else { return nil }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        let marker = data.subdata(in: 4..<8)
        if marker == Data("ftyp".utf8) {
            let brand = String(data: data.subdata(in: 8..<12), encoding: .ascii)?.lowercased() ?? ""
            if ["heic", "heix", "hevc", "mif1", "msf1", "heif"].contains(brand) {
                return .heic
            }
        }
        return nil
    }
}

enum LocalAttachmentStore {
    static let maxBytes = 10_000_000
    static var overrideDirectory: URL?
    static var failNextWrite = false

    static func directory() -> URL {
        if let overrideDirectory {
            try? FileManager.default.createDirectory(at: overrideDirectory, withIntermediateDirectories: true)
            return overrideDirectory
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("YouthAISubsidyDocuments", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func fileURL(for document: CaseDocument) -> URL {
        directory().appendingPathComponent(document.localRelativePath)
    }

    static func save(
        data: Data,
        type: DocumentType,
        caseId: String,
        isSynthetic: Bool,
        replacing existing: [CaseDocument]
    ) throws -> CaseDocument {
        guard !data.isEmpty else { throw LocalAttachmentError.emptyFile }
        guard data.count <= maxBytes else { throw LocalAttachmentError.tooLarge }
        let format = DetectedImageFormat.detect(data)
        let isPDF = data.starts(with: Data("%PDF-".utf8)) && (PDFDocument(data: data)?.pageCount ?? 0) > 0
        guard isPDF || (format != nil && UIImage(data: data) != nil) else {
            throw LocalAttachmentError.unsupportedFormat
        }
        if failNextWrite {
            failNextWrite = false
            throw LocalAttachmentError.writeFailed
        }

        let fileName = "\(isSynthetic ? "synthetic" : "local")-\(type.rawValue)-\(UUID().uuidString).\(isPDF ? "pdf" : format!.fileExtension)"
        var url = directory().appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            throw LocalAttachmentError.writeFailed
        }

        if let old = existing.first(where: { $0.type == type }) {
            removeFile(old)
        }

        return CaseDocument(
            id: UUID().uuidString,
            type: type,
            fileName: fileName,
            localRelativePath: fileName,
            isSynthetic: isSynthetic,
            attachedAt: Date(),
            uploadedAt: nil,
            byteCount: data.count,
            contentType: isPDF ? "application/pdf" : format!.contentType
        )
    }

    static func loadImage(for document: CaseDocument) -> UIImage? {
        let url = fileURL(for: document)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return UIImage(data: data)
    }

    static func removeFile(_ document: CaseDocument) {
        let url = fileURL(for: document)
        try? FileManager.default.removeItem(at: url)
    }

    static func cleanup(keeping documents: [CaseDocument]) {
        let keep = Set(documents.map(\.localRelativePath))
        let folder = directory()
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return
        }
        for url in items where !keep.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func removeAll() {
        let folder = directory()
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
}
