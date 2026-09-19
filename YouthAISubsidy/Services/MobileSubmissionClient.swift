import Foundation
import UIKit

/// 單次送件的網路契約。只使用設定於 App 建置中的 HTTPS API，不接受畫面手填網址。
enum MobileSubmissionClient {
    struct Receipt: Decodable {
        struct CaseInfo: Decodable {
            let caseId: String
            let status: CaseStatus
        }
        let `case`: CaseInfo
        let accessToken: String
    }

    struct Status: Decodable {
        let caseId: String
        let status: CaseStatus
        let statusNote: String?
    }

    private static func day(_ date: Date) -> String {
        ContractJSON.dateFormatter.string(from: date)
    }

    static func payload(for item: SubsidyCase) throws -> Data {
        let a = item.applicant
        let p = item.purchase
        let form = item.formFields
        let applicant: [String: Any] = [
            "fullName": a.fullName, "birthDate": day(a.birthDate), "isHsinchuResident": a.isHsinchuResident,
            "householdAddress": a.householdAddress, "contactEmail": a.contactEmail, "phone": a.phone,
            "identityCategory": a.identityCategory.rawValue,
            "specialIdentityKinds": a.specialIdentityKinds.map(\.rawValue),
            "culturalLanguageKinds": a.culturalLanguageKinds.map(\.rawValue),
            "bankName": a.bankName, "bankAccountMasked": a.bankAccountMasked,
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
                "twdAmount": NSDecimalNumber(decimal: p.twdPaidAmount.value).stringValue,
            ]],
        ]
        let fields: [String: Any] = [
            "nationalID": form.nationalID, "householdPostalCode": form.householdPostalCode,
            "householdDistrict": form.householdDistrict,
            "mailingSameAsHousehold": form.mailingSameAsHousehold,
            "mailingPostalCode": form.mailingPostalCode, "mailingCity": form.mailingCity,
            "mailingDistrict": form.mailingDistrict, "mailingStreet": form.mailingStreet,
            "monthlyPeriods": form.monthlyPeriods,
            "receiptConfirmations": Array(form.receiptConfirmations).sorted(),
        ]
        let documents: [[String: Any]] = try item.documents.map { document in
            let url = LocalAttachmentStore.fileURL(for: document)
            let original = try Data(contentsOf: url)
            guard !original.isEmpty, original.count <= LocalAttachmentStore.maxBytes else {
                throw CaseRepositoryError.remoteFailed("附件無法讀取或超過 10 MB：\(document.type.zhTitle)")
            }
            var bytes = original
            var contentType = document.contentType
            if contentType == "image/heic" {
                guard let jpeg = UIImage(data: original)?.jpegData(compressionQuality: 0.85),
                      jpeg.count <= LocalAttachmentStore.maxBytes else {
                    throw CaseRepositoryError.remoteFailed("無法轉換 HEIC 附件：\(document.type.zhTitle)")
                }
                bytes = jpeg
                contentType = "image/jpeg"
            }
            return ["type": document.type.rawValue, "contentType": contentType, "base64": bytes.base64EncodedString()]
        }
        return try JSONSerialization.data(withJSONObject: [
            "applicant": applicant, "purchase": purchase, "form": fields, "documents": documents,
        ])
    }

    static func submit(_ item: SubsidyCase, baseURL: URL, session: URLSession = .shared) async throws -> Receipt {
        guard baseURL.scheme == "https", baseURL.host != nil,
              let key = AppEnvironment.configuredClientKey else {
            throw CaseRepositoryError.remoteFailed("尚未設定可用的 HTTPS 收件服務。")
        }
        var request = URLRequest(url: baseURL.appending(path: "v1/mobile-submissions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-App-Key")
        request.httpBody = try payload(for: item)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw CaseRepositoryError.remoteFailed("後端尚未收妥申請，資料仍留在手機；請稍後重試。")
        }
        return try JSONDecoder().decode(Receipt.self, from: data)
    }

    static func status(caseId: String, accessToken: String, baseURL: URL, session: URLSession = .shared) async throws -> Status {
        var request = URLRequest(url: baseURL.appending(path: "v1/cases/\(caseId)"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CaseRepositoryError.remoteFailed("暫時讀不到案件最新進度。")
        }
        return try JSONDecoder().decode(Status.self, from: data)
    }
}
