import SwiftUI

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                DemoBanner()
                PrototypeDisclaimer()
            }
            Section("這支 App 會做什麼") {
                Text("協助青年逐步填寫官方要求資料、附上適用文件、閱讀兩則 AI 資安宣導，並查看自己送出後的進度。只會顯示你自己的案件；補件內容只在承辦正式通知時顯示，審查決定由承辦人在試算表人工完成。")
                    .font(.footnote)
            }
            Section("資料與附件") {
                Text("相簿選到的影像先存在本機，畫面會標「僅存本機、尚未上傳」。只有按「送出申請」且收件服務回覆成功後，附件才會傳到試算表收件服務。")
                    .font(.footnote)
            }
            Section("金鑰與 API") {
                Text("App 不會要你輸入 API 網址或金鑰；缺少收件憑證時，送出會明確失敗，不會假裝已送出。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                    .accessibilityIdentifier("about.noApiKey")
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
