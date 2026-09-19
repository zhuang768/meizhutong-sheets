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
                VStack(alignment: .leading, spacing: 8) {
                    Text("青年 AI 工具補助")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("填寫資料、附上文件，隨時查看申請進度。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }
                Button("開始新申請") {
                    model.startBlank()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .frame(minHeight: AppTheme.minTouch)
                .accessibilityIdentifier("home.startBlank")

                Text("梅竹通為競賽原型，尚未連接市府申辦系統。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)

            }
            .padding(16)
        }
        .appScreenBackground()
        .navigationTitle("梅竹通")
    }
}
