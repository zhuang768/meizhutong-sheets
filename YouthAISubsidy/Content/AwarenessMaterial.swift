import Foundation

/// Replaceable AI security cards. Drop images named `AwarenessCard1` / `AwarenessCard2`
/// into Assets.xcassets and edit the copy below. These are team drafts, not government notices.
enum AwarenessMaterial {
    struct Card: Identifiable, Hashable {
        var id: String
        var assetName: String
        var title: String
        var body: String
        var designerNote: String
    }

    static let cards: [Card] = [
        Card(
            id: "awareness-1",
            assetName: "AwarenessCard1",
            title: "申請文件請留在本機",
            body: "身分證、存摺、收據與付款資料只應作為本申請附件。請不要把它們傳送到聊天機器人、雲端相簿分享連結或未授權的外部工具。",
            designerNote: "圖一：待設計師提供。替換 Assets.xcassets 的 AwarenessCard1，並改這段標題與內文即可。"
        ),
        Card(
            id: "awareness-2",
            assetName: "AwarenessCard2",
            title: "AI 金鑰不是市府申辦鑰匙",
            body: "個人的 GPT 或其他模型 API key 不是政府申辦金鑰，也不該寫進這支 App。未來若有輔助檢查，金鑰不會放在青年端，青年端也不會把附件內容送到聊天機器人。",
            designerNote: "圖二：待設計師提供。替換 Assets.xcassets 的 AwarenessCard2，並改這段標題與內文即可。"
        )
    ]
}
