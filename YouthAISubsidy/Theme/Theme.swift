import SwiftUI

enum AppTheme {
    static let primary = Color(red: 30 / 255, green: 64 / 255, blue: 175 / 255)
    static let background = Color(red: 239 / 255, green: 246 / 255, blue: 255 / 255)
    static let card = Color.white
    static let ink = Color(red: 30 / 255, green: 58 / 255, blue: 138 / 255)
    static let muted = Color(red: 71 / 255, green: 85 / 255, blue: 105 / 255)
    static let accent = Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255)
    static let danger = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)
    static let warning = Color(red: 180 / 255, green: 83 / 255, blue: 9 / 255)
    static let minTouch: CGFloat = 44
}

enum ROCDate {
    static let calendar = Calendar(identifier: .gregorian)

    static let birthMin = date(year: 1985, month: 4, day: 3)
    static let birthMax = date(year: 2010, month: 4, day: 2)
    static let purchaseMin = date(year: 2026, month: 4, day: 2)
    static let purchaseMax = date(year: 2026, month: 10, day: 31)
    static let applyDeadline = date(year: 2026, month: 11, day: 30)

    static func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components) ?? Date()
    }

    static func display(_ date: Date) -> String {
        let year = calendar.component(.year, from: date) - 1911
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "民國 \(year) 年 \(month) 月 \(day) 日"
    }

    static func isoDay(_ date: Date) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func parseISODay(_ raw: String) -> Date? {
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return date(year: parts[0], month: parts[1], day: parts[2])
    }
}

enum ContractJSON {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .formatted(dateFormatter)
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        return decoder
    }
}
