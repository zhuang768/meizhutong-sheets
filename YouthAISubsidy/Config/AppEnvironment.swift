import Foundation

enum AppEnvironment {
    static let apiBaseURLDefaultsKey = "apiBaseURL"

    /// 只有建置時配置的固定 HTTPS 收件服務能啟用網路送件；舊的手機設定值不算。
    static var isRemoteAPIEnabled: Bool {
        configuredBaseURL?.scheme == "https" && configuredBaseURL?.host != nil && configuredClientKey != nil
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
        !isRemoteAPIEnabled
    }

    static var connectionLabel: String {
        isRemoteAPIEnabled
            ? "已連接試算表收件服務；不是市府正式申辦系統。"
            : "尚未連接市府申辦系統；資料只保存在這支手機，非正式案件。"
    }

    static func discardStaleConnectionSettings() {
        UserDefaults.standard.removeObject(forKey: apiBaseURLDefaultsKey)
    }

    static func setBaseURLString(_ raw: String) {
        _ = raw
        UserDefaults.standard.removeObject(forKey: apiBaseURLDefaultsKey)
    }
}
