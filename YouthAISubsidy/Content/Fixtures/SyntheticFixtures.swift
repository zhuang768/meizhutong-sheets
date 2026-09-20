import Foundation

enum SyntheticFixtures {
    static let generalId = "CASE-DEMO-GENERAL-001"
    static let specialId = "CASE-DEMO-SPECIAL-002"
    static let proxyId = "CASE-DEMO-PROXY-003"

    static var fixtureIds: Set<String> {
        [generalId, specialId, proxyId]
    }

    static func isFixtureCaseId(_ caseId: String) -> Bool {
        fixtureIds.contains(caseId)
    }

    static var all: [SubsidyCase] {
        [generalYouth(), specialNeedsDocuments(), proxyUnderReview()]
    }

    static func template(id: String) -> SubsidyCase {
        switch id {
        case specialId: return fillableSpecial()
        case proxyId: return fillableProxy()
        default: return fillableGeneral()
        }
    }

    static func generalYouth() -> SubsidyCase {
        var item = fillableGeneral()
        item.status = .submitted
        item.precheck = Precheck(
            eligibilityHints: ["合成預檢：欄位齊備，仍須人工審查。"],
            documentGaps: [],
            estimatedSubsidyTWD: DecimalString(320),
            disclaimer: "預估補助 320 元，非核定金額。",
            source: "synthetic-fixture"
        )
        item.auditEvents = [
            AuditEvent(at: ROCDate.date(year: 2026, month: 9, day: 1), actor: "youth-app-demo", action: "submitted", note: "合成送出，非正式案件。")
        ]
        return item
    }

    static func specialNeedsDocuments() -> SubsidyCase {
        var item = fillableSpecial()
        item.status = .needsDocuments
        item.precheck = Precheck(
            eligibilityHints: ["合成預檢：特定對象 90% 試算。"],
            documentGaps: ["官方收據未見軟體公司名稱（合成補件示範）。"],
            estimatedSubsidyTWD: DecimalString(1620),
            disclaimer: "預估補助 1,620 元，非核定金額。補件狀態來自合成後端結果。",
            source: "synthetic-fixture"
        )
        item.auditEvents = [
            AuditEvent(at: ROCDate.date(year: 2026, month: 9, day: 5), actor: "backend-demo", action: "needs_documents", note: "合成缺件通知，非正式承辦意見。")
        ]
        return item
    }

    static func proxyUnderReview() -> SubsidyCase {
        var item = fillableProxy()
        item.status = .underManualReview
        item.precheck = Precheck(
            eligibilityHints: ["合成預檢：代付文件已附，進入人工審查。"],
            documentGaps: [],
            estimatedSubsidyTWD: DecimalString(1600),
            disclaimer: "預估補助 1,600 元，非核定金額。審查中狀態來自合成後端。",
            source: "synthetic-fixture"
        )
        item.auditEvents = [
            AuditEvent(at: ROCDate.date(year: 2026, month: 9, day: 8), actor: "backend-demo", action: "under_manual_review", note: "合成人工審查中。")
        ]
        return item
    }

    static func fillableGeneral() -> SubsidyCase {
        var item = SubsidyCase.blank(caseId: generalId)
        item.localForm = .synthetic
        item.applicant = Applicant(
            fullName: "合成／林青禾",
            birthDate: ROCDate.date(year: 1998, month: 6, day: 15),
            isHsinchuResident: true,
            householdAddress: "新竹市東區合成路 0 號（非正式住址）",
            contactEmail: "demo.general@example.test",
            phone: "0900-000-001",
            identityCategory: .generalYouth,
            specialIdentityKinds: [],
            culturalLanguageKinds: [],
            bankName: "合成銀行",
            bankAccountMasked: "末四碼 0000（合成）",
            nationalIdPresenceNote: "合成影像已準備，非正式字號。"
        )
        item.purchase = Purchase(
            toolCategory: .other,
            toolName: "Cursor",
            vendorName: "Anysphere",
            vendorRegionCompliant: true,
            purchaseChannel: .officialWebsite,
            subscriptionPlan: .yearly,
            subscriptionStart: ROCDate.date(year: 2026, month: 8, day: 1),
            subscriptionEnd: ROCDate.date(year: 2027, month: 7, day: 31),
            purchaseDate: ROCDate.date(year: 2026, month: 8, day: 1),
            originalAmount: DecimalString(20),
            originalCurrency: "USD",
            twdPaidAmount: DecimalString(640),
            paymentMethod: "信用卡（不蒐集卡號）",
            isPrepaidCreditOrToken: false,
            isProxyPaid: false,
            proxyPayerName: "",
            proxyPayerRelation: ""
        )
        item.documents = []
        item.status = .draft
        return item
    }

    static func fillableSpecial() -> SubsidyCase {
        var item = SubsidyCase.blank(caseId: specialId)
        item.localForm = .synthetic
        item.applicant = Applicant(
            fullName: "合成／陳竹安",
            birthDate: ROCDate.date(year: 2001, month: 3, day: 20),
            isHsinchuResident: true,
            householdAddress: "新竹市北區展示街 1 號（非正式住址）",
            contactEmail: "demo.special@example.test",
            phone: "0900-000-002",
            identityCategory: .specialTarget,
            specialIdentityKinds: [.lowIncome],
            culturalLanguageKinds: [],
            bankName: "合成銀行",
            bankAccountMasked: "末四碼 0002（合成）",
            nationalIdPresenceNote: "合成影像已準備，非正式字號。"
        )
        item.purchase = Purchase(
            toolCategory: .general,
            toolName: "ChatGPT",
            vendorName: "OpenAI",
            vendorRegionCompliant: true,
            purchaseChannel: .officialWebsite,
            subscriptionPlan: .monthly,
            subscriptionStart: ROCDate.date(year: 2026, month: 6, day: 20),
            subscriptionEnd: ROCDate.date(year: 2026, month: 9, day: 19),
            purchaseDate: ROCDate.date(year: 2026, month: 8, day: 20),
            originalAmount: DecimalString(20),
            originalCurrency: "USD",
            twdPaidAmount: DecimalString(1800),
            paymentMethod: "信用卡（不蒐集卡號）",
            isPrepaidCreditOrToken: false,
            isProxyPaid: false,
            proxyPayerName: "",
            proxyPayerRelation: ""
        )
        return item
    }

    static func fillableProxy() -> SubsidyCase {
        var item = SubsidyCase.blank(caseId: proxyId)
        item.localForm = .synthetic
        item.applicant = Applicant(
            fullName: "合成／黃少竹",
            birthDate: ROCDate.date(year: 2009, month: 11, day: 2),
            isHsinchuResident: true,
            householdAddress: "新竹市香山區樣本巷 2 號（非正式住址）",
            contactEmail: "demo.proxy@example.test",
            phone: "0900-000-003",
            identityCategory: .generalYouth,
            specialIdentityKinds: [],
            culturalLanguageKinds: [],
            bankName: "合成銀行",
            bankAccountMasked: "末四碼 0003（合成）",
            nationalIdPresenceNote: "合成影像已準備，非正式字號。"
        )
        item.purchase = Purchase(
            toolCategory: .general,
            toolName: "Claude",
            vendorName: "Anthropic",
            vendorRegionCompliant: true,
            purchaseChannel: .officialWebsite,
            subscriptionPlan: .yearly,
            subscriptionStart: ROCDate.date(year: 2026, month: 8, day: 1),
            subscriptionEnd: ROCDate.date(year: 2027, month: 7, day: 31),
            purchaseDate: ROCDate.date(year: 2026, month: 8, day: 1),
            originalAmount: DecimalString(100),
            originalCurrency: "USD",
            twdPaidAmount: DecimalString(3200),
            paymentMethod: "法定代理人信用卡（不蒐集卡號）",
            isPrepaidCreditOrToken: false,
            isProxyPaid: true,
            proxyPayerName: "合成／黃監護",
            proxyPayerRelation: "父母"
        )
        return item
    }
}
