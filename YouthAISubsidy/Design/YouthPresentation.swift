import Foundation

enum YouthSupplementDisplay: Equatable {
    case none
    case awaitingOfficialExplanation
    case syntheticDemo([String])
}

enum SyntheticSupplementCatalog {
    static func messages(for item: SubsidyCase) -> [String]? {
        guard SyntheticFixtures.isFixtureCaseId(item.caseId), item.status == .needsDocuments else {
            return nil
        }
        switch item.caseId {
        case SyntheticFixtures.specialId:
            return ["官方收據未見軟體公司名稱（合成補件示範，非正式承辦通知）。"]
        default:
            return nil
        }
    }
}

enum YouthPresentation {
    static func displayCaseId(_ caseId: String) -> String {
        caseId.replacingOccurrences(of: "DEMO-", with: "")
    }

    static func isFixtureCaseId(_ caseId: String) -> Bool {
        SyntheticFixtures.isFixtureCaseId(caseId)
    }

    static func ownCases(from cases: [SubsidyCase]) -> [SubsidyCase] {
        cases.filter { !isFixtureCaseId($0.caseId) }
    }

    static func supplementDisplay(for item: SubsidyCase) -> YouthSupplementDisplay {
        if let messages = SyntheticSupplementCatalog.messages(for: item) {
            return .syntheticDemo(messages)
        }
        if item.status == .needsDocuments {
            return .awaitingOfficialExplanation
        }
        return .none
    }

    static func attachmentStatusText(for document: CaseDocument?) -> String {
        guard let document else { return "尚未填齊" }
        if document.isSynthetic {
            return "合成檔（僅存本機、尚未上傳）"
        }
        if document.contentType == "application/pdf" {
            return "本機 PDF（僅存本機、尚未上傳）"
        }
        return "本機照片（僅存本機、尚未上傳）"
    }
}
