import Foundation
import UIKit

/// Excel 第 1–20 筆合成情境，經 App 收件契約寫入試算表。App 不產生核准或駁回。
enum SyntheticLoadTest {
    static let caseIdPrefix = "MZT-LOADTEST-"
    static let batchSize = 20
    static let importCap = 20
    static let submittedIdsKey = "spreadsheet.batch.submittedIds"

    enum DocumentVariant: String, Codable {
        case match
        case idMismatch
        case receiptMismatch
        case unsignedAffidavit
        case none
        case skipPassbook
    }

    private struct Payload: Decodable {
        let datasetTotal: Int
        let batchSize: Int
        let rows: [Row]
    }

    struct Row: Decodable {
        let caseId: String
        let scenario: String
        let documentVariant: DocumentVariant
        let fullName: String
        let nationalID: String
        let birthDate: String
        let phone: String
        let contactEmail: String
        let isHsinchuResident: Bool
        let identityCategory: String
        let specialIdentityKinds: String
        let culturalLanguageKinds: String
        let householdPostalCode: String
        let householdDistrict: String
        let householdAddress: String
        let mailingSameAsHousehold: Bool
        let mailingPostalCode: String
        let mailingCity: String
        let mailingDistrict: String
        let mailingStreet: String
        let bankName: String
        let bankAccountMasked: String
        let subscriptionPlan: String
        let monthlyPeriods: Int
        let toolCategory: String
        let toolName: String
        let vendorName: String
        let vendorRegionCompliant: Bool
        let purchaseChannel: String
        let purchaseDate: String
        let subscriptionStart: String
        let subscriptionEnd: String
        let originalCurrency: String
        let originalAmount: String
        let twdPaidAmount: String
        let paymentMethod: String
        let isPrepaidCreditOrToken: Bool
        let isProxyPaid: Bool
        let proxyPayerName: String
        let proxyPayerRelation: String
        let receiptBuyer: Bool
        let receiptStatement: Bool
        let receiptCard: Bool
        let receiptTool: Bool
        let receiptVendor: Bool
        let receiptDate: Bool
        let receiptAmount: Bool
        let receiptTwd: Bool
    }

    private static let payload: Payload? = {
        guard let data = NSDataAsset(name: "SyntheticAppBatch", bundle: Bundle(for: ApplicationFlowModel.self))?.data else {
            return nil
        }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }()

    static var datasetTotal: Int { payload?.datasetTotal ?? 0 }
    static var rows: [Row] { payload?.rows ?? [] }

    static func isLoadTestCaseId(_ caseId: String) -> Bool {
        caseId.hasPrefix(caseIdPrefix)
    }

    static func submittedIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: submittedIdsKey) ?? [])
    }

    static func markSubmitted(_ caseId: String) {
        var ids = submittedIds()
        ids.insert(caseId)
        UserDefaults.standard.set(Array(ids).sorted(), forKey: submittedIdsKey)
    }

    static func resetProgress() {
        UserDefaults.standard.removeObject(forKey: submittedIdsKey)
    }

    struct PreparedCase {
        var item: SubsidyCase
        let variant: DocumentVariant
        let scenario: String
    }

    static func nextBatch(skipping submitted: Set<String> = submittedIds(), limit: Int = batchSize) -> [PreparedCase] {
        let room = importCap - submitted.filter(isLoadTestCaseId).count
        let take = min(limit, room)
        guard take > 0 else { return [] }
        var batch: [PreparedCase] = []
        for row in rows where batch.count < take {
            guard let item = makeCase(row), !submitted.contains(item.caseId) else { continue }
            batch.append(PreparedCase(item: item, variant: row.documentVariant, scenario: row.scenario))
        }
        return batch
    }

    static func makeCase(_ row: Row) -> SubsidyCase? {
        guard let identity = IdentityCategory(rawValue: row.identityCategory),
              let plan = SubscriptionPlan(rawValue: row.subscriptionPlan),
              let category = ToolCategory(rawValue: row.toolCategory) else { return nil }

        var defaulted: [String] = []
        func date(_ raw: String, _ label: String, fallback: Date) -> Date {
            if let parsed = ROCDate.parseISODay(raw) { return parsed }
            defaulted.append(label)
            return fallback
        }
        let birthDate = date(row.birthDate, "出生日期", fallback: Applicant.blank.birthDate)
        let purchaseDate = date(row.purchaseDate, "購買日期", fallback: Purchase.blank.purchaseDate)
        let subscriptionStart = date(row.subscriptionStart, "訂閱起日", fallback: Purchase.blank.subscriptionStart)
        let subscriptionEnd = date(row.subscriptionEnd, "訂閱迄日", fallback: Purchase.blank.subscriptionEnd)
        let channel: PurchaseChannel
        if let parsed = PurchaseChannel(rawValue: row.purchaseChannel) {
            channel = parsed
        } else {
            defaulted.append("購買管道")
            channel = Purchase.blank.purchaseChannel
        }

        var fields = ApplicationFormFields()
        fields.nationalID = row.nationalID
        fields.householdPostalCode = row.householdPostalCode
        fields.householdDistrict = row.householdDistrict
        fields.mailingSameAsHousehold = row.mailingSameAsHousehold
        fields.mailingPostalCode = row.mailingPostalCode
        fields.mailingCity = row.mailingCity
        fields.mailingDistrict = row.mailingDistrict
        fields.mailingStreet = row.mailingStreet
        fields.monthlyPeriods = row.monthlyPeriods
        fields.receiptConfirmations = Set(
            [
                ("buyer", row.receiptBuyer), ("statement", row.receiptStatement),
                ("card", row.receiptCard), ("tool", row.receiptTool),
                ("vendor", row.receiptVendor), ("date", row.receiptDate),
                ("amount", row.receiptAmount), ("twd", row.receiptTwd)
            ].compactMap { $0.1 ? $0.0 : nil }
        )

        var item = SubsidyCase(
            caseId: row.caseId,
            applicant: Applicant(
                fullName: row.fullName,
                birthDate: birthDate,
                isHsinchuResident: row.isHsinchuResident,
                householdAddress: row.householdAddress,
                contactEmail: row.contactEmail,
                phone: row.phone,
                identityCategory: identity,
                specialIdentityKinds: splitList(row.specialIdentityKinds).compactMap(SpecialIdentityKind.init(rawValue:)),
                culturalLanguageKinds: splitList(row.culturalLanguageKinds).compactMap(CulturalLanguageKind.init(rawValue:)),
                bankName: row.bankName,
                bankAccountMasked: row.bankAccountMasked,
                nationalIdPresenceNote: Applicant.blank.nationalIdPresenceNote
            ),
            purchase: Purchase(
                toolCategory: category,
                toolName: row.toolName,
                vendorName: row.vendorName,
                vendorRegionCompliant: row.vendorRegionCompliant,
                purchaseChannel: channel,
                subscriptionPlan: plan,
                subscriptionStart: subscriptionStart,
                subscriptionEnd: subscriptionEnd,
                purchaseDate: purchaseDate,
                originalAmount: DecimalString(Decimal(string: row.originalAmount) ?? 0),
                originalCurrency: row.originalCurrency,
                twdPaidAmount: DecimalString(Decimal(string: row.twdPaidAmount) ?? 0),
                paymentMethod: row.paymentMethod,
                isPrepaidCreditOrToken: row.isPrepaidCreditOrToken,
                isProxyPaid: row.isProxyPaid,
                proxyPayerName: row.proxyPayerName,
                proxyPayerRelation: row.proxyPayerRelation
            ),
            documents: [],
            precheck: nil,
            status: .draft,
            auditEvents: [],
            localForm: fields
        )
        var note = "合成批次送件，情境 \(row.scenario)；非正式案件，狀態不是核准或駁回。"
        if !defaulted.isEmpty {
            note += "資料集缺漏的欄位以預設值代替：" + defaulted.joined(separator: "、") + "。"
        }
        item.auditEvents = [AuditEvent(at: Date(), actor: "youth-app-demo", action: "spreadsheet_batch", note: note)]
        return item
    }

    static func attachDocuments(to item: inout SubsidyCase, variant: DocumentVariant) throws {
        guard variant != .none else { return }
        let types = FormValidator.requiredDocumentTypes(for: item).filter { type in
            !(variant == .skipPassbook && type == .passbookCover)
        }
        var attached: [CaseDocument] = []
        for type in types {
            let data = SyntheticDocumentFactory.makeImage(type: type, item: item, variant: variant)
            attached.append(try LocalAttachmentStore.save(
                data: data, type: type, caseId: item.caseId, isSynthetic: true, replacing: []
            ))
        }
        item.documents = attached
    }

    private static func splitList(_ raw: String) -> [String] {
        raw.split(whereSeparator: { ",|、".contains($0) }).map(String.init).filter { !$0.isEmpty }
    }
}
