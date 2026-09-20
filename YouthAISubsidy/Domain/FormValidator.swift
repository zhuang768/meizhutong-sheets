import Foundation

enum FormValidator {
    static func issues(
        for draft: SubsidyCase,
        step: WizardStep? = nil,
        referenceDate: Date = Date()
    ) -> [ValidationIssue] {
        switch step {
        case .applicant: return applicantIssues(draft)
        case .purchase: return purchaseIssues(draft, referenceDate: referenceDate)
        case .documents: return documentIssues(draft)
        case .awareness: return []
        case .review, .none:
            return applicantIssues(draft) + purchaseIssues(draft, referenceDate: referenceDate) + documentIssues(draft)
        }
    }

    static func requiredDocumentTypes(for draft: SubsidyCase) -> [DocumentType] {
        var types: [DocumentType] = [
            .idFront, .idBack, .officialReceipt, .twdConversionProof,
            .paymentProof, .cardLast4NamePhoto, .passbookCover, .signedAffidavit
        ]
        if draft.applicant.identityCategory == .specialTarget {
            types.append(.specialIdentityProof)
        }
        if draft.applicant.identityCategory == .culturalLanguageKeeper {
            types.append(.culturalLanguageCertificate)
        }
        if draft.purchase.isProxyPaid {
            types.append(contentsOf: [.kinshipProof, .proxyPaymentAffidavit])
        }
        return types
    }

    static func missingDocumentTypes(for draft: SubsidyCase) -> [DocumentType] {
        let present = Set(draft.documents.map(\.type))
        return requiredDocumentTypes(for: draft).filter { !present.contains($0) }
    }

    private static func applicantIssues(_ draft: SubsidyCase) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let applicant = draft.applicant
        let form = draft.formFields
        if form.nationalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "applicant.nationalID", message: "請填寫身分證字號；合成測試可使用 TEST-ID-ONLY。"))
        }
        if form.householdPostalCode.isEmpty || form.householdDistrict.isEmpty {
            issues.append(.init(field: "applicant.householdDetails", message: "請填寫戶籍郵遞區號並選擇行政區。"))
        }
        if !form.mailingSameAsHousehold && [form.mailingPostalCode, form.mailingCity, form.mailingDistrict, form.mailingStreet].contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append(.init(field: "applicant.mailingAddress", message: "請完整填寫通訊地址，或勾選同戶籍地址。"))
        }
        if applicant.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "applicant.fullName", message: "請填寫申請人姓名。"))
        }
        if applicant.birthDate < ROCDate.birthMin || applicant.birthDate > ROCDate.birthMax {
            issues.append(.init(field: "applicant.birthDate", message: "出生日期須為民國 74 年 4 月 3 日至 99 年 4 月 2 日。"))
        }
        if !applicant.isHsinchuResident {
            issues.append(.init(field: "applicant.isHsinchuResident", message: "申請人須設籍新竹市。"))
        }
        if !applicant.householdAddress.contains("新竹市") {
            issues.append(.init(field: "applicant.householdAddress", message: "戶籍地址須包含「新竹市」，且須與身分證影像可辨識住址一致。"))
        }
        if !applicant.contactEmail.contains("@") {
            issues.append(.init(field: "applicant.contactEmail", message: "請填寫電子郵件。"))
        }
        if applicant.phone.trimmingCharacters(in: .whitespacesAndNewlines).count < 8 {
            issues.append(.init(field: "applicant.phone", message: "請填寫聯絡電話。"))
        }
        if applicant.identityCategory == .specialTarget && applicant.specialIdentityKinds.isEmpty {
            issues.append(.init(field: "applicant.specialIdentityKinds", message: "特定對象請至少勾選一種身分。"))
        }
        if applicant.identityCategory == .culturalLanguageKeeper && applicant.culturalLanguageKinds.isEmpty {
            issues.append(.init(field: "applicant.culturalLanguageKinds", message: "文化語言保存者請至少勾選一種證照。"))
        }
        return issues
    }

    private static func purchaseIssues(_ draft: SubsidyCase, referenceDate: Date) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let purchase = draft.purchase
        if purchase.subscriptionPlan == .monthly && draft.formFields.monthlyPeriods < 1 {
            issues.append(.init(field: "purchase.monthlyPeriods", message: "月費期數至少為 1 期。"))
        }
        for item in ApplicationFormFields.receiptItems where !draft.formFields.receiptConfirmations.contains(item.id) {
            issues.append(.init(field: "purchase.receipt.\(item.id)", message: "請確認憑證：\(item.title)。"))
        }
        if purchase.toolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "purchase.toolName", message: "請填寫完整 AI 工具名稱（非空間）。"))
        }
        if purchase.vendorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "purchase.vendorName", message: "請填寫軟體公司／賣方名稱。"))
        }
        if !purchase.vendorRegionCompliant {
            issues.append(.init(field: "purchase.vendorRegionCompliant", message: "須確認該工具非中國（含港澳）廠商開發或營運。"))
        }
        if !purchase.purchaseChannel.isEligible {
            issues.append(.init(field: "purchase.purchaseChannel", message: "僅補助直接向 AI 軟體官方網站購買。"))
        }
        if purchase.isPrepaidCreditOrToken {
            issues.append(.init(field: "purchase.isPrepaidCreditOrToken", message: "預付儲值、Credit、點數、Token 或 API 額度不予補助。"))
        }
        if purchase.purchaseDate < ROCDate.purchaseMin || purchase.purchaseDate > ROCDate.purchaseMax {
            issues.append(.init(field: "purchase.purchaseDate", message: "購買日期須為民國 115 年 4 月 2 日至 10 月 31 日。"))
        }
        if purchase.subscriptionEnd < purchase.subscriptionStart {
            issues.append(.init(field: "purchase.subscriptionEnd", message: "訂閱結束日不可早於開始日。"))
        }
        if purchase.originalAmount.value <= 0 {
            issues.append(.init(field: "purchase.originalAmount", message: "請填寫大於 0 的原始費用。"))
        }
        if purchase.originalCurrency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "purchase.originalCurrency", message: "請填寫原始費用幣別。"))
        }
        if purchase.twdPaidAmount.value <= 0 {
            issues.append(.init(field: "purchase.twdPaidAmount", message: "請填寫大於 0 的臺幣實付／帳單金額。"))
        }
        if purchase.paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "purchase.paymentMethod", message: "請填寫付款方式。請勿輸入完整卡號。"))
        }
        let allowedMonths = purchase.subscriptionPlan.applyWithinMonths
        if let latest = ROCDate.calendar.date(byAdding: .month, value: allowedMonths, to: purchase.purchaseDate),
           ROCDate.calendar.startOfDay(for: referenceDate) > ROCDate.calendar.startOfDay(for: latest)
        {
            let unit = purchase.subscriptionPlan == .monthly ? "一個月" : "兩個月"
            issues.append(.init(field: "purchase.purchaseDate", message: "\(purchase.subscriptionPlan.zhTitle)須於購買後\(unit)內提出申請。"))
        }
        if purchase.isProxyPaid {
            if purchase.proxyPayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(field: "purchase.proxyPayerName", message: "代付時請填寫代付人姓名。"))
            }
            if purchase.proxyPayerRelation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(field: "purchase.proxyPayerRelation", message: "代付時請填寫與申請人關係（父母、配偶或法定代理人）。"))
            }
        }
        return issues
    }

    private static func documentIssues(_ draft: SubsidyCase) -> [ValidationIssue] {
        missingDocumentTypes(for: draft).map { type in
            ValidationIssue(field: "documents.\(type.rawValue)", message: "尚未填齊，尚未檢附：\(type.zhTitle)。")
        }
    }
}

enum WizardStep: Int, CaseIterable, Hashable {
    case applicant
    case purchase
    case documents
    case awareness
    case review

    var title: String {
        switch self {
        case .applicant: return "申請人與資格"
        case .purchase: return "AI 工具與購買"
        case .documents: return "應備文件"
        case .awareness: return "AI 資安宣導"
        case .review: return "摘要與送出"
        }
    }

    var next: WizardStep? {
        WizardStep(rawValue: rawValue + 1)
    }

    var previous: WizardStep? {
        WizardStep(rawValue: rawValue - 1)
    }
}
