import SwiftUI

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                DemoBanner()
                PrototypeDisclaimer()
            }
            Section("這支 App 會做什麼") {
                Text("協助青年逐步填寫官方要求資料、附上適用文件、閱讀兩則 AI 資安宣導，並查看自己送出後的進度。補件內容只在承辦正式通知時顯示。")
                    .font(.footnote)
                Text("不會顯示其他人的案件、內部 AI 預審或管理員設定。審查決定只由承辦人在試算表人工完成。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
            }
            Section("資料與附件") {
                Text("這不是正式案件。\(AppEnvironment.connectionLabel)")
                    .font(.footnote)
                    .accessibilityIdentifier("about.localOnly")
                Text("相簿選到的影像先存在本機，畫面會標「僅存本機、尚未上傳」。只有按「送出申請」且收件服務回覆成功後，附件才會傳到試算表收件服務。")
                    .font(.footnote)
            }
            Section("金鑰與 API") {
                Text("個人的 GPT 或其他模型 API key 不是政府申辦金鑰。禁止把它寫進 Git 或聊天。內嵌測試憑證可被擷取，不能當正式身分驗證。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.warning)
                    .accessibilityIdentifier("about.noApiKey")
                Text("青年畫面不提供 API 網址或金鑰輸入。只有建置時寫入的收件服務可送件；缺憑證時會明確失敗，不會假裝已送出。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
            }
            Section("來源") {
                Text("官方公開說明：dgservice.hccg.gov.tw 服務公告 id=1323")
                    .font(.footnote)
                Text("本 App 未連接正式政府系統，也不上架 App Store。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .navigationTitle("說明")
    }
}
