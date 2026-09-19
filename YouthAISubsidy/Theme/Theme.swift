import SwiftUI
import UIKit

enum AppTheme {
    static let primary = Color(
        light: UIColor(r: 30, g: 64, b: 175),
        dark: UIColor(r: 10, g: 132, b: 255)
    )
    static let background = Color(
        light: UIColor(r: 239, g: 246, b: 255),
        dark: UIColor(r: 15, g: 23, b: 42)
    )
    static let card = Color(
        light: .white,
        dark: UIColor(r: 30, g: 41, b: 59)
    )
    static let ink = Color(
        light: UIColor(r: 30, g: 58, b: 138),
        dark: UIColor(r: 241, g: 245, b: 249)
    )
    static let muted = Color(
        light: UIColor(r: 71, g: 85, b: 105),
        dark: UIColor(r: 203, g: 213, b: 225)
    )
    static let accent = Color(
        light: UIColor(r: 22, g: 163, b: 74),
        dark: UIColor(r: 74, g: 222, b: 128)
    )
    static let danger = Color(
        light: UIColor(r: 220, g: 38, b: 38),
        dark: UIColor(r: 248, g: 113, b: 113)
    )
    static let warning = Color(
        light: UIColor(r: 180, g: 83, b: 9),
        dark: UIColor(r: 251, g: 191, b: 36)
    )
    static let subtleFill = Color(
        light: UIColor(r: 226, g: 232, b: 240),
        dark: UIColor(r: 51, g: 65, b: 85)
    )
    static let dangerFill = Color(
        light: UIColor(r: 254, g: 226, b: 226),
        dark: UIColor(r: 69, g: 10, b: 10)
    )
    static let placeholderFill = Color(
        light: UIColor(r: 241, g: 245, b: 249),
        dark: UIColor(r: 51, g: 65, b: 85)
    )
    static let minTouch: CGFloat = 44

    static func wizardAccent(for step: WizardStep) -> Color {
        switch step {
        case .applicant:
            return Color(light: UIColor(r: 73, g: 101, b: 188), dark: UIColor(r: 64, g: 156, b: 255))
        case .purchase:
            return Color(light: UIColor(r: 63, g: 89, b: 173), dark: UIColor(r: 32, g: 139, b: 255))
        case .documents:
            return Color(light: UIColor(r: 52, g: 78, b: 161), dark: UIColor(r: 10, g: 132, b: 255))
        case .awareness:
            return Color(light: UIColor(r: 40, g: 67, b: 148), dark: UIColor(r: 10, g: 122, b: 245))
        case .review:
            return primary
        }
    }
}

extension View {
    func appScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(AppTheme.background)
    }
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

private extension UIColor {
    convenience init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.init(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
}

private extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
