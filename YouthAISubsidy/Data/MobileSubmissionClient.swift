import Foundation
import UIKit

/// 試算表方案的單次送件契約。只使用建置時設定的 HTTPS 網址。
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

    private struct SubmissionEnvelope: Decodable {
        let ok: Bool
        let `case`: Receipt.CaseInfo?
        let accessToken: String?
        let error: String?
    }

    private struct StatusEnvelope: Decodable {
        let ok: Bool
        let caseId: String?
        let status: CaseStatus?
        let statusNote: String?
        let error: String?
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
        var totalBytes = 0
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
            totalBytes += bytes.count
            guard totalBytes <= 25 * 1024 * 1024 else {
                throw CaseRepositoryError.remoteFailed("附件總量超過單次送件 25 MB，請縮小圖片後重試。")
            }
            return ["type": document.type.rawValue, "contentType": contentType, "base64": bytes.base64EncodedString()]
        }
        return try JSONSerialization.data(withJSONObject: [
            "clientSubmissionId": item.caseId,
            "applicant": applicant, "purchase": purchase, "form": fields, "documents": documents,
        ])
    }

    static func submit(
        _ item: SubsidyCase,
        baseURL: URL,
        clientKey: String? = AppEnvironment.configuredClientKey,
        session: URLSession = .shared
    ) async throws -> Receipt {
        guard baseURL.scheme == "https", baseURL.host != nil,
              let key = clientKey, !key.isEmpty else {
            throw CaseRepositoryError.remoteFailed("尚未設定可用的 HTTPS 收件服務。")
        }
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard var body = try JSONSerialization.jsonObject(with: payload(for: item)) as? [String: Any] else {
            throw CaseRepositoryError.remoteFailed("申請資料無法建立，請檢查填寫內容。")
        }
        body["action"] = "submit"
        body["clientKey"] = key
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CaseRepositoryError.remoteFailed("試算表收件服務尚未回覆，資料仍留在手機；請稍後重試。")
        }
        let envelope = try JSONDecoder().decode(SubmissionEnvelope.self, from: data)
        guard envelope.ok, let info = envelope.case, let token = envelope.accessToken else {
            throw CaseRepositoryError.remoteFailed(envelope.error ?? "試算表尚未收妥申請。")
        }
        return Receipt(case: info, accessToken: token)
    }

    static func status(
        caseId: String,
        accessToken: String,
        baseURL: URL,
        clientKey: String? = AppEnvironment.configuredClientKey,
        session: URLSession = .shared
    ) async throws -> Status {
        guard let key = clientKey, !key.isEmpty else {
            throw CaseRepositoryError.remoteFailed("試算表查詢服務尚未設定。")
        }
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "action": "status", "clientKey": key,
            "caseId": caseId, "accessToken": accessToken,
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CaseRepositoryError.remoteFailed("暫時讀不到案件最新進度。")
        }
        let envelope = try JSONDecoder().decode(StatusEnvelope.self, from: data)
        guard envelope.ok, let receivedCaseId = envelope.caseId, let status = envelope.status else {
            throw CaseRepositoryError.remoteFailed(envelope.error ?? "暫時讀不到案件最新進度。")
        }
        return Status(caseId: receivedCaseId, status: status, statusNote: envelope.statusNote)
    }
}
