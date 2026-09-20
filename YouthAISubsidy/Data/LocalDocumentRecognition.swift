import Foundation
import Vision
import PDFKit

/// On-device OCR candidates are shown for review, never treated as identity verification.
/// Document text is never sent to a server or written to logs.
struct RecognizedSample: Identifiable {
    let id = UUID()
    let type: DocumentType
    let imageData: Data
    var reverseImageData: Data?
    var name: String?
    var documentNumber: String?
    var birthDate: Date?
    var address: String?
    var postalCode: String?
    var toolName: String?
    var vendorName: String?
    var purchaseDate: Date?
    var originalAmount: Decimal?
    var currency: String?
    var twdAmount: Decimal?
    var isGeneratedSample = false

    var hasFields: Bool {
        if type == .idFront || type == .idBack {
            return name != nil || documentNumber != nil || birthDate != nil || address != nil || postalCode != nil
        }
        return toolName != nil || vendorName != nil || purchaseDate != nil || originalAmount != nil || twdAmount != nil
    }
}

enum LocalDocumentRecognitionError: LocalizedError {
    case notSynthetic, noFields, notIdentityCard

    var errorDescription: String? {
        switch self {
        case .notSynthetic: return "這不是明確標示的合成測試文件。"
        case .noFields: return "沒有辨識到可帶入的欄位，請維持手動填寫。"
        case .notIdentityCard: return "無法確認照片中有國民身分證欄位，請重拍清楚的正反面。"
        }
    }
}

enum LocalDocumentRecognition {
    static func recognizeSynthetic(_ data: Data, type: DocumentType) throws -> RecognizedSample {
        let lines = try imageLines(from: data)
        return try parseSynthetic(lines: lines, type: type, imageData: data)
    }

    static func recognizeIdentity(front: Data, back: Data) throws -> RecognizedSample {
        let frontLines = try imageLines(from: front)
        let backLines = try imageLines(from: back)
        let frontText = frontLines.joined(separator: " ").uppercased()
        let backText = backLines.joined(separator: " ").uppercased()
        if frontText.contains("SYNTHETIC") || backText.contains("SYNTHETIC") {
            let frontResult = try parseSynthetic(lines: frontLines, type: .idFront, imageData: front)
            let backResult = try parseSynthetic(lines: backLines, type: .idBack, imageData: back)
            return combinedSyntheticID(front: frontResult, back: backResult)
        }
        return try parseIdentity(frontLines: frontLines, backLines: backLines, frontImage: front, backImage: back)
    }

    /// Parses printed labels conservatively. OCR is not a proof of identity or card authenticity.
    static func parseIdentity(
        frontLines: [String], backLines: [String], frontImage: Data = Data(), backImage: Data = Data()
    ) throws -> RecognizedSample {
        let frontText = frontLines.joined().replacingOccurrences(of: " ", with: "")
        let backText = backLines.joined().replacingOccurrences(of: " ", with: "")
        guard frontText.contains("國民身分證") || frontText.contains("中華民國") else {
            throw LocalDocumentRecognitionError.notIdentityCard
        }
        guard backText.contains("住址") || backText.contains("戶籍地址") else {
            throw LocalDocumentRecognitionError.notIdentityCard
        }
        var result = RecognizedSample(type: .idFront, imageData: frontImage)
        result.reverseImageData = backImage
        result.name = labeledCapture(in: frontLines, pattern: #"姓\s*名\s*[:：]?\s*([\p{Han}]{2,6})"#)
        let normalized = frontLines.joined(separator: " ")
            .uppercased().replacingOccurrences(of: " ", with: "")
        if let candidate = firstMatch(in: normalized, pattern: #"[A-Z][12][0-9]{8}"#),
           isValidNationalID(candidate) {
            result.documentNumber = candidate
        }
        result.birthDate = rocBirthDate(in: frontLines)
        result.address = labeledCapture(in: backLines, pattern: #"(?:戶籍地址|住\s*址)\s*[:：]?\s*([^\s]{6,60})"#)
        guard result.hasFields else { throw LocalDocumentRecognitionError.noFields }
        return result
    }

    /// Reads a local image or PDF. The source file and OCR text never leave this device.
    static func recognizeLocalReceipt(_ data: Data) throws -> RecognizedSample {
        if let pdf = PDFDocument(data: data), let firstPage = pdf.page(at: 0) {
            let image = firstPage.thumbnail(of: CGSize(width: 1600, height: 2200), for: .mediaBox)
            let preview = image.pngData() ?? Data()
            let embedded = firstPage.string ?? ""
            let lines = embedded.components(separatedBy: .newlines).filter { !$0.isEmpty }
            if let result = try? parseReceipt(lines: lines, imageData: preview) { return result }
            return try parseReceipt(lines: imageLines(from: preview), imageData: preview)
        }
        return try parseReceipt(lines: imageLines(from: data), imageData: data)
    }

    private static func imageLines(from data: Data) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hant", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(data: data).perform([request])
        return (request.results ?? [])
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { $0.topCandidates(1).first?.string }
    }

    static func parseSynthetic(lines: [String], type: DocumentType, imageData: Data = Data()) throws -> RecognizedSample {
        let joined = lines.joined(separator: " ").uppercased()
        guard joined.contains("SYNTHETIC"), joined.contains("NOT REAL") else {
            throw LocalDocumentRecognitionError.notSynthetic
        }
        var result = RecognizedSample(type: type, imageData: imageData)
        if type == .idFront {
            result.name = value(in: lines, label: "Name")
            if joined.contains("TEST-ID-ONLY") { result.documentNumber = "TEST-ID-ONLY" }
            result.birthDate = parseDate(value(in: lines, label: "Birth"))
        } else if type == .idBack {
            result.address = value(in: lines, label: "Address")
            result.postalCode = value(in: lines, label: "ZIP")
        } else if type == .officialReceipt {
            result = try parseReceipt(lines: lines, imageData: imageData)
        }
        guard result.hasFields else { throw LocalDocumentRecognitionError.noFields }
        return result
    }

    static func combinedSyntheticID(front: RecognizedSample, back: RecognizedSample) -> RecognizedSample {
        var result = front
        result.address = back.address
        result.postalCode = back.postalCode
        result.reverseImageData = back.imageData
        return result
    }

    /// Label-aware candidates, not a vendor-specific template or approval decision.
    static func parseReceipt(lines: [String], imageData: Data = Data()) throws -> RecognizedSample {
        var result = RecognizedSample(type: .officialReceipt, imageData: imageData)
        result.toolName = firstValue(in: lines, labels: ["Tool", "Product", "Item", "軟體名稱", "品名"])
        result.vendorName = firstValue(in: lines, labels: ["Vendor", "Seller", "Merchant", "賣方", "商家"])
        if result.vendorName == nil,
           let line = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("receipt from ") }),
           let range = line.range(of: "Receipt from ", options: .caseInsensitive) {
            result.vendorName = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if result.toolName == nil,
           let line = lines.first(where: { $0.localizedCaseInsensitiveContains("Subscription") && amount(in: $0) != nil }),
           let currencyRange = line.range(of: "NT$") ?? line.range(of: "USD") {
            let candidate = line[..<currencyRange.lowerBound].trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty { result.toolName = candidate }
        }
        let dateValue = firstValue(in: lines, labels: ["Payment Date", "Purchase Date", "Date", "付款日期", "購買日期"])
            ?? lines.first(where: { $0.localizedCaseInsensitiveContains("Paid ") })?
                .replacingOccurrences(of: "Paid ", with: "", options: .caseInsensitive)
        result.purchaseDate = parseDate(dateValue)

        let prioritized = lines.filter { line in
            ["total", "paid", "amount", "金額", "費用"].contains {
                line.localizedCaseInsensitiveContains($0)
            }
        }
        for line in prioritized + lines {
            guard let candidate = amount(in: line) else { continue }
            result.currency = candidate.currency
            result.originalAmount = candidate.value
            if candidate.currency == "TWD" { result.twdAmount = candidate.value }
            break
        }
        if let explicitlyTWD = lines.compactMap({ line -> Decimal? in
            guard line.localizedCaseInsensitiveContains("TWD") || line.contains("NT$") else { return nil }
            return amount(in: line)?.value
        }).first {
            result.twdAmount = explicitlyTWD
        }
        guard result.hasFields else { throw LocalDocumentRecognitionError.noFields }
        return result
    }

    private static func firstValue(in lines: [String], labels: [String]) -> String? {
        for label in labels {
            if let found = value(in: lines, label: label) { return found }
        }
        return nil
    }

    private static func amount(in line: String) -> (currency: String, value: Decimal)? {
        let pattern = #"(?i)(NT\$|TWD|USD|US\$|EUR|€|\$)\s*[:：]?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let currencyRange = Range(match.range(at: 1), in: line),
              let amountRange = Range(match.range(at: 2), in: line),
              let value = Decimal(string: String(line[amountRange]).replacingOccurrences(of: ",", with: "")) else { return nil }
        let symbol = String(line[currencyRange]).uppercased()
        let currency = ["NT$", "TWD"].contains(symbol) ? "TWD" : ["US$", "$", "USD"].contains(symbol) ? "USD" : "EUR"
        return (currency, value)
    }

    private static func value(in lines: [String], label: String) -> String? {
        for line in lines where line.localizedCaseInsensitiveContains(label) {
            guard let colon = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        for format in ["yyyy/MM/dd", "yyyy-MM-dd", "MMMM d, yyyy", "MMM d, yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines)) { return date }
        }
        return nil
    }

    private static func labeledCapture(in lines: [String], pattern: String) -> String? {
        for line in lines {
            if let value = firstMatch(in: line, pattern: pattern, group: 1) {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    private static func rocBirthDate(in lines: [String]) -> Date? {
        let pattern = #"(?:出生|生\s*日|民國)\s*[:：]?\s*(?:民國)?\s*(\d{2,4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日"#
        for line in lines {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let yearRange = Range(match.range(at: 1), in: line),
                  let monthRange = Range(match.range(at: 2), in: line),
                  let dayRange = Range(match.range(at: 3), in: line),
                  let year = Int(line[yearRange]), let month = Int(line[monthRange]), let day = Int(line[dayRange])
            else { continue }
            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = TimeZone(secondsFromGMT: 0)
            components.year = year < 1000 ? year + 1911 : year
            components.month = month
            components.day = day
            if let date = components.date,
               Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date).day == day {
                return date
            }
        }
        return nil
    }

    private static func isValidNationalID(_ value: String) -> Bool {
        guard value.count == 10, let letter = value.first else { return false }
        // Official letter mapping is non-sequential for I, O, W and Z.
        let map: [Character: Int] = [
            "A": 10, "B": 11, "C": 12, "D": 13, "E": 14, "F": 15, "G": 16, "H": 17,
            "I": 34, "J": 18, "K": 19, "L": 20, "M": 21, "N": 22, "O": 35, "P": 23,
            "Q": 24, "R": 25, "S": 26, "T": 27, "U": 28, "V": 29, "W": 32, "X": 30,
            "Y": 31, "Z": 33
        ]
        guard let prefix = map[letter] else { return false }
        let digits = value.dropFirst().compactMap(\.wholeNumberValue)
        guard digits.count == 9 else { return false }
        let values = [prefix / 10, prefix % 10] + digits
        let weights = [1, 9, 8, 7, 6, 5, 4, 3, 2, 1, 1]
        return zip(values, weights).reduce(0) { $0 + $1.0 * $1.1 } % 10 == 0
    }
}
