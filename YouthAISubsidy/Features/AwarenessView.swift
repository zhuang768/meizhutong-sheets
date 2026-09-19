import SwiftUI
import UIKit

struct AwarenessView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("以下兩則是團隊準備的 AI 資安宣導版位，不是政府公告，也不構成本申請的審查或認證。正式圖文待設計師提供後，只須替換圖片與短文。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                    .accessibilityIdentifier("awareness.disclaimer")
                ForEach(Array(AwarenessMaterial.cards.enumerated()), id: \.element.id) { index, card in
                    awarenessCard(card, index: index + 1)
                }
            }
            .padding(16)
        }
        .background(AppTheme.background)
    }

    private func awarenessCard(_ card: AwarenessMaterial.Card, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("圖文 \(index)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
            if let image = UIImage(named: card.assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel(card.title)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("待設計師提供")
                        .font(.headline)
                        .accessibilityIdentifier("awareness.placeholder.\(card.id)")
                    Text(card.designerNote)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 241 / 255, green: 245 / 255, blue: 249 / 255))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text(card.title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text(card.body)
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("awareness.card.\(card.id)")
    }
}
