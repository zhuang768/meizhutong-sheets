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
                Text("不會顯示承辦工作台、其他人的案件、內部 AI 預審或管理員設定。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
            }
            Section("資料與附件") {
                Text("資料與附件只存在這支 iPhone；目前未連接市府申辦系統，這不是正式案件。")
                    .font(.footnote)
                    .accessibilityIdentifier("about.localOnly")
                Text("相簿選到的影像只存在本機，畫面會標「僅存本機、尚未上傳」。在附件上傳契約確認前，App 不會把證件、存摺、付款資料或照片送到外部。")
                    .font(.footnote)
            }
            Section("金鑰與 API") {
                Text("個人的 GPT 或其他模型 API key 不是政府申辦金鑰。禁止把它寫進 iOS App、程式碼、測試資料、日誌或 Git。未來 AI 只能由隊友後端保管金鑰並提供受控 API。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.warning)
                    .accessibilityIdentifier("about.noApiKey")
                Text("青年畫面不提供 API 網址或金鑰輸入。即使裝置留有舊網址，本版本也不會傳送申請資料。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
            }
            Section("仍待隊友 API 契約") {
                Text("待對齊：案件建立／查詢／補件、欄位大小寫與日期金額格式、附件上傳方式、驗證與錯誤格式、查詢授權。詳見 docs/API_CONTRACT_QUESTIONS.md。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                    .accessibilityIdentifier("about.contractPending")
            }
            Section("來源") {
                Text("官方公開說明：dgservice.hccg.gov.tw 服務公告 id=1323")
                    .font(.footnote)
                Text("本 App 未連接正式政府系統，也不上架 App Store。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
            }
            Section("開發測試") {
                NavigationLink("合成測試案例") { DemoSandboxView() }
                    .accessibilityIdentifier("about.openDemo")
            }
        }
        .navigationTitle("說明")
    }
}
