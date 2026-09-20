import SwiftUI

struct HomeView: View {
    @Environment(ApplicationFlowModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image("SubsidyCampaign")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("新竹市 AI 領航青年數位工具補助計畫宣傳圖")
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text("青年 AI 工具補助")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("填寫資料、附上文件，隨時查看申請進度。")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .multilineTextAlignment(.center)
                    Button("開始新申請") {
                        model.startBlank()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                    .frame(minHeight: AppTheme.minTouch)
                    .accessibilityIdentifier("home.startBlank")
                }
                .frame(maxWidth: .infinity)

                spreadsheetBatchCard

                Text("梅竹通為競賽原型，尚未連接市府申辦系統。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)

            }
            .padding(16)
        }
        .appScreenBackground()
        .navigationTitle("梅竹通")
        .task { model.loadSpreadsheetBatchProgress() }
    }

    private var spreadsheetBatchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("合成 20 筆 → 試算表")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text("與桌面 Excel 第 1–20 筆同一組情境。按一下會寫入試算表並附合成身分證、發票、切結書；App 不會核准或駁回。未連接收件服務時不會假裝已送出。")
                .font(.footnote)
                .foregroundStyle(AppTheme.muted)
            Text("已送出 \(model.spreadsheetBatchSubmittedCount) / \(SyntheticLoadTest.importCap) 筆")
                .font(.subheadline)
                .accessibilityIdentifier("home.batchProgress")
            Button("送出 20 筆到試算表") {
                Task { await model.submitSpreadsheetBatch() }
            }
            .buttonStyle(.bordered)
            .frame(minHeight: AppTheme.minTouch)
            .disabled(model.isSubmittingSpreadsheetBatch || model.isBusy || model.spreadsheetBatchSubmittedCount >= SyntheticLoadTest.importCap)
            .accessibilityIdentifier("home.submitBatch")
            if model.isSubmittingSpreadsheetBatch {
                ProgressView()
            }
            if let banner = model.banner {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                    .accessibilityIdentifier("home.batchFeedback")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
