# 梅竹通｜試算表承辦方案

此儲存庫維護青年端 iOS App，以及 Google 試算表收件與 AI 輔助查核。承辦人直接在試算表審查，不另做 Web 工作台。

## 預期流程

1. 青年在 App 填妥官方要求的欄位與附件，按一次「送出申請」。
2. 收件服務保存完整案件與附件，並將案件欄位及附件連結寫入雲端試算表。
3. 確定性規則標示缺件與格式問題；AI 只提供可追溯的查核建議，不自動核准或駁回。
4. 承辦人在試算表中決定補件、核准或駁回；App 讀回自己的案件狀態。

照片與 PDF 不應塞進儲存格；試算表記錄受控的附件連結。申請人資料、查核建議、人工決定與處理紀錄應分欄或分頁保存，不能把 AI 意見當成核定結果。

## 目前狀態

**真機可一次送出合成申請並寫入試算表**；同一案件重送不會新增第二筆。人工審查分頁的決定可由 App「我的案件」下拉讀回。不得對外宣稱可正式受理市府申請。

已選定 Google 試算表。可見分頁為「申請案件」、「申請資料」、「附件」、「AI 查核」、「人工審查」；原本 69 欄保留在隱藏的 `_原始資料_69欄` 工作表。收件程式先寫入原始資料，再按案件編號寫入五個分頁。Web App 已部署，無憑證請求會被拒絕。**AI 查核與手機推播尚未實作。** 金鑰與登入憑證不能提交到 Git。

執行欄位對應測試：`node scripts/schema.test.js`。

## 試算表收件程式

`sheets/FiveTabLayout.gs` 定義五分頁版面，`sheets/Schema.gs` 與 `sheets/Server.gs` 是收件與查詢程式。可執行 `node scripts/schema.test.js` 與 `node scripts/server.test.js` 做不連網的合成資料測試。

本機設定：

1. 由試算表擁有者在 Apps Script「專案設定 → 指令碼屬性」自行設定測試專用 `CLIENT_KEY`。金鑰不要貼到聊天或提交到 Git。
2. 複製 `Config/Secrets.xcconfig.example` 為 `Config/Secrets.xcconfig`（已列入 `.gitignore`），填入同一把測試金鑰後執行 `make generate`。不要把金鑰寫進 `project.yml` 或 Xcode 專案檔。固定 HTTPS 收件網址已在 App 專案中設定。App 不提供使用者手填網址或第二次同步按鈕。
3. 用一筆合成申請在實體手機按「送出申請」，核對試算表與附件連結；人工改「人工審查」分頁後，再在手機「我的案件」下拉更新。

Apps Script 方案目前限制單檔 10 MB、單次送件附件總量 25 MB，支援 JPEG、PNG、PDF。試算表和 Drive 授權會讓程式以擁有者身分寫入資料；內含在手機程式中的測試金鑰可被逆向取得，不能當作正式受理真實證件的登入機制。

## 本機建置

需 macOS、Xcode 與 XcodeGen。若尚未有本機憑證檔，`make generate` 會從範本建立空白的 `Config/Secrets.xcconfig`。憑證填好後再開啟產生的 Xcode 專案。測試可用 `make test`；建置可用 `make build`。不要把 `Config/Secrets.xcconfig` 加入 Git。
