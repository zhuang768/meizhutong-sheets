import Foundation

/// Shared case contract keys with the teammate backend.
/// Field names below are a client-side reading until the official API contract arrives.
struct SubsidyCase: Codable, Identifiable, Hashable {
    var caseId: String
    var applicant: Applicant
    var purchase: Purchase
    var documents: [CaseDocument]
    var precheck: Precheck?
    var status: CaseStatus
    var auditEvents: [AuditEvent]
    /// Local form supplement; teammate API mapping must be agreed before remote use.
    var localForm: ApplicationFormFields?
    /// 承辦人對申請人公開的補件或處理說明；不得放入內部備註。
    var publicStatusNote: String? = nil

    var formFields: ApplicationFormFields {
        get { localForm ?? ApplicationFormFields() }
        set { localForm = newValue }
    }

    var id: String { caseId }

    static func blank(caseId: String = "DRAFT-LOCAL") -> SubsidyCase {
        SubsidyCase(
            caseId: caseId,
            applicant: .blank,
            purchase: .blank,
            documents: [],
            precheck: nil,
            status: .draft,
            auditEvents: [
                AuditEvent(
                    at: Date(),
                    actor: "youth-app",
                    action: "draft_created",
                    note: "本機建立草稿，非正式案件。"
                )
            ]
        )
    }
}

struct ApplicationFormFields: Codable, Hashable {
    var nationalID = ""
    var householdPostalCode = ""
    var householdDistrict = ""
    var mailingSameAsHousehold = false
    var mailingPostalCode = ""
    var mailingCity = ""
    var mailingDistrict = ""
    var mailingStreet = ""
    var monthlyPeriods = 1
    var receiptConfirmations: Set<String> = []

    static let receiptItems: [(id: String, title: String)] = [
        ("buyer", "收據證明註明購買人"),
        ("statement", "信用卡帳單扣款紀錄可證明購買品項及名稱"),
        ("card", "已附信用卡簽名及末四碼證明，其他卡號已遮蔽"),
        ("tool", "軟體名稱"), ("vendor", "軟體公司名稱"),
        ("date", "購買日期"), ("amount", "原始費用"), ("twd", "換算新臺幣")
    ]

    static var synthetic: ApplicationFormFields {
        var fields = ApplicationFormFields()
        fields.nationalID = "TEST-ID-ONLY"
        fields.householdPostalCode = "300"
        fields.householdDistrict = "東區"
        fields.mailingSameAsHousehold = true
        fields.receiptConfirmations = Set(receiptItems.map(\.id))
        return fields
    }
}

enum CaseStatus: String, Codable, CaseIterable, Hashable {
    case draft
    case submitted
    case needsDocuments = "needs_documents"
    case underManualReview = "under_manual_review"
    case approved
    case rejected

    var zhTitle: String {
        switch self {
        case .draft: return "草稿"
        case .submitted: return "已送出（待後端處理）"
        case .needsDocuments: return "需補件"
        case .underManualReview: return "人工審查中"
        case .approved: return "已核准（後端人工結果）"
        case .rejected: return "已駁回（後端人工結果）"
        }
    }

    var isTerminalDecision: Bool {
        self == .approved || self == .rejected
    }
}

enum IdentityCategory: String, Codable, CaseIterable, Hashable {
    case generalYouth
    case specialTarget
    case culturalLanguageKeeper

    var zhTitle: String {
        switch self {
        case .generalYouth: return "一般青年"
        case .specialTarget: return "特定對象"
        case .culturalLanguageKeeper: return "文化語言保存者"
        }
    }

    var subsidyRate: Decimal { self == .generalYouth ? Decimal(string: "0.5")! : Decimal(string: "0.9")! }
    var subsidyCapTWD: Decimal { self == .generalYouth ? 3000 : 6000 }
}

enum SpecialIdentityKind: String, Codable, CaseIterable, Hashable {
    case lowIncome
    case midLowIncome
    case soleBreadwinner
    case disability
    case indigenous
    case newImmigrant
    case employmentServiceAct24

    var zhTitle: String {
        switch self {
        case .lowIncome: return "低收入戶"
        case .midLowIncome: return "中低收入戶"
        case .soleBreadwinner: return "獨立負擔家計者"
        case .disability: return "身心障礙者"
        case .indigenous: return "原住民"
        case .newImmigrant: return "新住民"
        case .employmentServiceAct24: return "就業服務法第24條第1項各款"
        }
    }
}

enum CulturalLanguageKind: String, Codable, CaseIterable, Hashable {
    case indigenousLanguage
    case taiwanese
    case hakka

    var zhTitle: String {
        switch self {
        case .indigenousLanguage: return "原住民族語言能力認證"
        case .taiwanese: return "臺灣台語語言能力認證"
        case .hakka: return "客語能力認證"
        }
    }
}

enum ToolCategory: String, Codable, CaseIterable, Hashable {
    case general
    case image
    case office
    case learning
    case other

    var zhTitle: String {
        switch self {
        case .general: return "通用型"
        case .image: return "影像類"
        case .office: return "辦公類"
        case .learning: return "學習類"
        case .other: return "其他類"
        }
    }
}

enum PurchaseChannel: String, Codable, CaseIterable, Hashable {
    case officialWebsite
    case aggregator
    case reseller

    var zhTitle: String {
        switch self {
        case .officialWebsite: return "AI 軟體官方網站"
        case .aggregator: return "集合式 AI 平台（例如 Poe.com，不予補助）"
        case .reseller: return "代購或其他非官方管道（不予補助）"
        }
    }

    var isEligible: Bool { self == .officialWebsite }
}

enum SubscriptionPlan: String, Codable, CaseIterable, Hashable {
    case monthly
    case yearly

    var zhTitle: String {
        switch self {
        case .monthly: return "月費制"
        case .yearly: return "年費制"
        }
    }

    var applyWithinMonths: Int { self == .monthly ? 1 : 2 }
}

struct Applicant: Codable, Hashable {
    var fullName: String
    var birthDate: Date
    var isHsinchuResident: Bool
    var householdAddress: String
    var contactEmail: String
    var phone: String
    var identityCategory: IdentityCategory
    var specialIdentityKinds: [SpecialIdentityKind]
    var culturalLanguageKinds: [CulturalLanguageKind]
    var bankName: String
    var bankAccountMasked: String
    var nationalIdPresenceNote: String

    static var blank: Applicant {
        Applicant(
            fullName: "",
            birthDate: ROCDate.date(year: 1998, month: 1, day: 1),
            isHsinchuResident: false,
            householdAddress: "",
            contactEmail: "",
            phone: "",
            identityCategory: .generalYouth,
            specialIdentityKinds: [],
            culturalLanguageKinds: [],
            bankName: "",
            bankAccountMasked: "",
            nationalIdPresenceNote: "身分證字號僅能出現在上傳影像，請勿在文字欄貼上真實字號。"
        )
    }
}

struct Purchase: Codable, Hashable {
    var toolCategory: ToolCategory
    var toolName: String
    var vendorName: String
    var vendorRegionCompliant: Bool
    var purchaseChannel: PurchaseChannel
    var subscriptionPlan: SubscriptionPlan
    var subscriptionStart: Date
    var subscriptionEnd: Date
    var purchaseDate: Date
    var originalAmount: DecimalString
    var originalCurrency: String
    var twdPaidAmount: DecimalString
    var paymentMethod: String
    var isPrepaidCreditOrToken: Bool
    var isProxyPaid: Bool
    var proxyPayerName: String
    var proxyPayerRelation: String

    static var blank: Purchase {
        Purchase(
            toolCategory: .other,
            toolName: "",
            vendorName: "",
            vendorRegionCompliant: true,
            purchaseChannel: .officialWebsite,
            subscriptionPlan: .yearly,
            subscriptionStart: ROCDate.purchaseMin,
            subscriptionEnd: ROCDate.date(year: 2027, month: 4, day: 1),
            purchaseDate: ROCDate.purchaseMin,
            originalAmount: DecimalString(0),
            originalCurrency: "USD",
            twdPaidAmount: DecimalString(0),
            paymentMethod: "",
            isPrepaidCreditOrToken: false,
            isProxyPaid: false,
            proxyPayerName: "",
            proxyPayerRelation: ""
        )
    }
}

enum DocumentType: String, Codable, CaseIterable, Hashable {
    case idFront
    case idBack
    case officialReceipt
    case twdConversionProof
    case paymentProof
    case cardLast4NamePhoto
    case passbookCover
    case signedAffidavit
    case specialIdentityProof
    case culturalLanguageCertificate
    case kinshipProof
    case proxyPaymentAffidavit

    var zhTitle: String {
        switch self {
        case .idFront: return "身分證正面"
        case .idBack: return "身分證背面"
        case .officialReceipt: return "官方收據"
        case .twdConversionProof: return "換算臺幣證明"
        case .paymentProof: return "繳款／出帳憑證"
        case .cardLast4NamePhoto: return "信用卡末四碼及姓名照片"
        case .passbookCover: return "存摺封面"
        case .signedAffidavit: return "親簽切結書（附件三）"
        case .specialIdentityProof: return "特定對象身分證明"
        case .culturalLanguageCertificate: return "本土語言證照證明"
        case .kinshipProof: return "代付親屬關係證明"
        case .proxyPaymentAffidavit: return "代付共同簽署切結書（附件四）"
        }
    }

    var officialNote: String {
        switch self {
        case .idFront, .idBack:
            return "須能辨識姓名、出生年月日、身分證字號、設籍新竹市住址。"
        case .officialReceipt:
            return "須含訂閱人姓名或電子信箱、完整 AI 名稱、軟體公司、日期、期間、原始費用、付款方式。"
        case .twdConversionProof:
            return "公開說明稱詳附件一；完整欄位待人工確認。"
        case .paymentProof:
            return "出帳帳單或繳款憑證。"
        case .cardLast4NamePhoto:
            return "公開說明列於購買憑證。本 App 不提供卡號輸入欄。"
        case .passbookCover:
            return "限申請人本人帳戶，供補助款匯入。"
        case .signedAffidavit:
            return "須親筆簽名後上傳。範本細節待人工確認。"
        case .specialIdentityProof:
            return "非特定對象免附。"
        case .culturalLanguageCertificate:
            return "非文化語言保存者免附。"
        case .kinshipProof:
            return "戶口名簿、戶籍謄本或其他足資證明。非代付免附。"
        case .proxyPaymentAffidavit:
            return "申請人與代付人共同親簽。非代付免附。"
        }
    }
}

struct CaseDocument: Codable, Identifiable, Hashable {
    var id: String
    var type: DocumentType
    var fileName: String
    var localRelativePath: String
    var isSynthetic: Bool
    var attachedAt: Date
    /// Contract placeholder. Local Demo never sets this; youth UI must not say uploaded.
    var uploadedAt: Date?
    var byteCount: Int
    var contentType: String

    var isUploaded: Bool { uploadedAt != nil }

    init(
        id: String,
        type: DocumentType,
        fileName: String,
        localRelativePath: String,
        isSynthetic: Bool,
        attachedAt: Date = Date(),
        uploadedAt: Date? = nil,
        byteCount: Int = 0,
        contentType: String = "image/png"
    ) {
        self.id = id
        self.type = type
        self.fileName = fileName
        self.localRelativePath = localRelativePath
        self.isSynthetic = isSynthetic
        self.attachedAt = attachedAt
        self.uploadedAt = uploadedAt
        self.byteCount = byteCount
        self.contentType = contentType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(DocumentType.self, forKey: .type)
        fileName = try container.decode(String.self, forKey: .fileName)
        localRelativePath = try container.decode(String.self, forKey: .localRelativePath)
        isSynthetic = try container.decode(Bool.self, forKey: .isSynthetic)
        attachedAt = try container.decodeIfPresent(Date.self, forKey: .attachedAt) ?? Date()
        uploadedAt = nil
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount) ?? 0
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType) ?? "image/png"
    }
}

struct Precheck: Codable, Hashable {
    var eligibilityHints: [String]
    var documentGaps: [String]
    var estimatedSubsidyTWD: DecimalString
    var disclaimer: String
    var source: String

    static func localEstimate(for draft: SubsidyCase) -> Precheck {
        let estimate = SubsidyEstimator.estimate(for: draft)
        return Precheck(
            eligibilityHints: estimate.hints,
            documentGaps: [],
            estimatedSubsidyTWD: DecimalString(estimate.amount),
            disclaimer: "預估補助為非正式試算，非核定金額。核准或駁回只能來自後端人工審查。",
            source: "youth-app-local-estimate"
        )
    }
}

struct AuditEvent: Codable, Identifiable, Hashable {
    var at: Date
    var actor: String
    var action: String
    var note: String

    var id: String { "\(action)-\(at.timeIntervalSince1970)" }
}

struct DecimalString: Codable, Hashable {
    var value: Decimal

    init(_ value: Decimal) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), let decimal = Decimal(string: string) {
            value = decimal
            return
        }
        if let decimal = try? container.decode(Decimal.self) {
            value = decimal
            return
        }
        if let double = try? container.decode(Double.self) {
            value = Decimal(double)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported money value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: value).stringValue)
    }

    var displayTWD: String {
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: number) ?? number.stringValue
    }
}

struct ValidationIssue: Identifiable, Hashable {
    var field: String
    var message: String
    var id: String { field + message }
}
