import Foundation

enum AppEnvironment {
    static let apiBaseURLDefaultsKey = "apiBaseURL"

    enum ConnectionState: Equatable {
        case localOnly
        case missingCredential
        case spreadsheetIntake
    }

    /// 只有建置時配置的固定 HTTPS 收件服務，且具備憑證，才能啟用網路送件。
    static var connectionState: ConnectionState {
        guard configuredBaseURL != nil else { return .localOnly }
        guard configuredClientKey != nil else { return .missingCredential }
        return .spreadsheetIntake
    }

    static var isRemoteAPIEnabled: Bool {
        connectionState == .spreadsheetIntake
    }

    static var configuredClientKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "APIClientKey") as? String else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty || key.contains("$(") ? nil : key
    }

    static var configuredBaseURL: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), url.scheme == "https", url.host != nil {
                return url
            }
        }
        return nil
    }

    static var isDemoMode: Bool {
        connectionState != .spreadsheetIntake
    }

    static var connectionLabel: String {
        connectionLabel(for: connectionState)
    }

    static var shortConnectionLabel: String {
        shortConnectionLabel(for: connectionState)
    }

    static func connectionLabel(for state: ConnectionState) -> String {
        switch state {
        case .localOnly:
            return "尚未連接市府申辦系統；資料只保存在這支手機，非正式案件。"
        case .missingCredential:
            return "已指定試算表收件網址，但尚未完成憑證設定；按送出不會寫入試算表。"
        case .spreadsheetIntake:
            return "已連接試算表收件服務；不是市府正式申辦系統。"
        }
    }

    static func shortConnectionLabel(for state: ConnectionState) -> String {
        switch state {
        case .localOnly:
            return "資料僅存這支手機・尚未送市府"
        case .missingCredential:
            return "收件憑證尚未設定・送出不會進表"
        case .spreadsheetIntake:
            return "試算表測試收件・非市府正式申辦"
        }
    }

    static func discardStaleConnectionSettings() {
        UserDefaults.standard.removeObject(forKey: apiBaseURLDefaultsKey)
    }
}
