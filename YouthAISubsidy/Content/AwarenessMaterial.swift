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
            title: "四個方法，讓 AI 回答更準確",
            body: "寫提示詞時交代目的、成果、對象、格式與限制；讓 AI 先問你問題來補齊需求；依任務選擇合適的工具；最後請它比較不同觀點、找出盲點，再由你自己核實與判斷。",
            designerNote: "圖二：待設計師提供。替換 Assets.xcassets 的 AwarenessCard2，並改這段標題與內文即可。"
        )
    ]
}
