import Foundation

/// 獨立於正式申辦 API 的合成資料連動。僅送表單欄位與合成附件種類，不傳影像或身分證字號。
enum SyntheticLinkClient {
    struct Link: Decodable {
        struct CaseInfo: Decodable {
            let caseId: String
            let status: String
        }
        let `case`: CaseInfo
        let accessToken: String
    }

    struct Status: Decodable {
        let caseId: String
        let status: String
        let statusNote: String?
    }

    static func baseURL(_ raw: String) throws -> URL {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http", url.port == 8791,
              let host = url.host, url.path.isEmpty || url.path == "/",
              url.user == nil, url.password == nil,
              host == "127.0.0.1" || host.hasPrefix("192.168.") || host.hasPrefix("10.") || private172(host)
        else { throw CaseRepositoryError.remoteFailed("請填入這部 Mac 的測試連線網址，使用同一 Wi-Fi 與埠號 8791。") }
        return url
    }

    private static func private172(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts[0] == "172" && (Int(parts[1]) ?? 0) >= 16 && (Int(parts[1]) ?? 0) <= 31
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    static func payload(for item: SubsidyCase) throws -> Data {
        guard item.applicant.fullName.hasPrefix("合成／"), item.applicant.contactEmail.hasSuffix(".test"),
              !item.documents.isEmpty, item.documents.allSatisfy(\.isSynthetic),
              FormValidator.issues(for: item).isEmpty
        else { throw CaseRepositoryError.remoteFailed("這條連線只可送出欄位完整、附件皆為合成檔的測試申請。") }
        let a = item.applicant
        let p = item.purchase
        let applicant: [String: Any] = [
            "fullName": a.fullName, "birthDate": day(a.birthDate), "isHsinchuResident": a.isHsinchuResident,
            "householdAddress": a.householdAddress, "contactEmail": a.contactEmail, "phone": a.phone,
            "identityCategory": a.identityCategory.rawValue,
            "specialIdentityKinds": a.specialIdentityKinds.map(\.rawValue),
            "culturalLanguageKinds": a.culturalLanguageKinds.map(\.rawValue),
            "bankName": a.bankName, "bankAccountMasked": a.bankAccountMasked
        ]
        let purchase: [String: Any] = [
            "toolCategory": p.toolCategory.rawValue, "toolName": p.toolName, "vendorName": p.vendorName,
            "vendorRegionCompliant": p.vendorRegionCompliant, "purchaseChannel": p.purchaseChannel.rawValue,
            "subscriptionPlan": p.subscriptionPlan.rawValue, "paymentMethod": p.paymentMethod,
            "isPrepaidCreditOrToken": p.isPrepaidCreditOrToken, "isProxyPaid": p.isProxyPaid,
            "proxyPayerName": p.isProxyPaid ? p.proxyPayerName : NSNull(),
            "proxyPayerRelation": p.isProxyPaid ? p.proxyPayerRelation : NSNull(),
            "charges": [[
                "chargeId": "app-1", "purchaseDate": day(p.purchaseDate),
                "periodStart": day(p.subscriptionStart), "periodEnd": day(p.subscriptionEnd),
                "originalAmount": NSDecimalNumber(decimal: p.originalAmount.value).stringValue,
                "originalCurrency": p.originalCurrency,
                "twdAmount": NSDecimalNumber(decimal: p.twdPaidAmount.value).stringValue
            ]]
        ]
        return try JSONSerialization.data(withJSONObject: [
            "synthetic": true, "applicant": applicant, "purchase": purchase,
            "documentTypes": item.documents.map { $0.type.rawValue }
        ])
    }

    static func submit(_ item: SubsidyCase, to rawURL: String) async throws -> Link {
        let url = try baseURL(rawURL).appending(path: "v1/synthetic-submissions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try payload(for: item)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 201 else {
            throw CaseRepositoryError.remoteFailed("合成案件未送入後端；請檢查服務是否啟動、手機與 Mac 是否在同一網路。")
        }
        return try JSONDecoder().decode(Link.self, from: data)
    }

    static func refresh(_ link: Link, at rawURL: String) async throws -> Status {
        let url = try baseURL(rawURL).appending(path: "v1/cases/\(link.case.caseId)")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(link.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CaseRepositoryError.remoteFailed("讀取合成案件狀態失敗；請確認後端沒有重新啟動。")
        }
        return try JSONDecoder().decode(Status.self, from: data)
    }
}
