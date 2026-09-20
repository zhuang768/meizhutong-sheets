import Foundation

struct SubsidyEstimate: Hashable {
    var amount: Decimal
    var rate: Decimal
    var cap: Decimal
    var hints: [String]
}

enum SubsidyEstimator {
    static func estimate(for draft: SubsidyCase) -> SubsidyEstimate {
        let category = draft.applicant.identityCategory
        let rate = category.subsidyRate
        let cap = category.subsidyCapTWD
        let paid = draft.purchase.twdPaidAmount.value
        let raw = paid * rate
        let amount = min(raw, cap)
        var hints: [String] = [
            "以臺幣實付金額試算，\(category.zhTitle)補助 \(percent(rate))，上限 \(cap.displayInt) 元。",
            "此金額為預估補助，非核定金額。"
        ]
        if draft.purchase.purchaseChannel != .officialWebsite {
            hints.append("購買管道不是官方網站時，公開說明不予補助。")
        }
        if draft.purchase.isPrepaidCreditOrToken {
            hints.append("預付儲值、Credit、點數、Token 或 API 額度不屬補助範圍。")
        }
        if !draft.purchase.vendorRegionCompliant {
            hints.append("中國（含港澳）開發或營運之工具不予補助。")
        }
        return SubsidyEstimate(amount: amount, rate: rate, cap: cap, hints: hints)
    }

    private static func percent(_ rate: Decimal) -> String {
        let percent = rate * 100
        return "\(NSDecimalNumber(decimal: percent).intValue)%"
    }
}

extension Decimal {
    var displayInt: String {
        NSDecimalNumber(decimal: self).stringValue
    }
}
