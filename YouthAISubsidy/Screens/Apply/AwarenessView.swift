import SwiftUI
import UIKit

struct AwarenessView: View {
    @State private var zoomedCard: AwarenessMaterial.Card?

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
        .appScreenBackground()
        .fullScreenCover(item: $zoomedCard) { card in
            ZoomableImageViewer(assetName: card.assetName, title: card.title)
        }
    }

    @ViewBuilder
    private func awarenessCard(_ card: AwarenessMaterial.Card, index: Int) -> some View {
        let image = UIImage(named: card.assetName)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("圖文 \(index)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                if image != nil {
                    Label("點圖放大", systemImage: "plus.magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                        .accessibilityHidden(true)
                }
            }
            if let image {
                Button {
                    zoomedCard = card
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(card.title)
                .accessibilityHint("點兩下放大圖片")
                .accessibilityIdentifier("awareness.zoom.\(card.id)")
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
                .background(AppTheme.placeholderFill)
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

private struct ZoomableImageViewer: View {
    let assetName: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image = UIImage(named: assetName) {
                ZoomableImageView(image: image, label: title)
                    .ignoresSafeArea()
            }
            Button("完成") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
                .padding(.horizontal, 16)
                .frame(minHeight: AppTheme.minTouch)
                .background(Color.white.opacity(0.92), in: Capsule())
                .padding(16)
                .accessibilityIdentifier("awareness.zoom.close")
        }
        .statusBarHidden()
    }
}

/// Pinch to zoom, drag to pan, double-tap to zoom in or reset. UIScrollView handles bounds and bounce.
private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let label: String

    func makeUIView(context: Context) -> ZoomScrollView {
        ZoomScrollView(image: image, label: label)
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {}
}

private final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    private var laidOutSize: CGSize = .zero

    init(image: UIImage, label: String) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = label
        imageView.accessibilityIdentifier = "awareness.zoom.image"
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != laidOutSize, let size = imageView.image?.size, size.width > 0, size.height > 0,
           bounds.width > 0, bounds.height > 0 {
            laidOutSize = bounds.size
            zoomScale = 1
            let fit = min(bounds.width / size.width, bounds.height / size.height)
            imageView.frame = CGRect(x: 0, y: 0, width: size.width * fit, height: size.height * fit)
            contentSize = imageView.frame.size
        }
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    private func centerImage() {
        var frame = imageView.frame
        frame.origin.x = max((bounds.width - frame.width) / 2, 0)
        frame.origin.y = max((bounds.height - frame.height) / 2, 0)
        imageView.frame = frame
    }

    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let target: CGFloat = 2.5
        let point = gesture.location(in: imageView)
        let size = CGSize(width: bounds.width / target, height: bounds.height / target)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                        width: size.width, height: size.height), animated: true)
    }
}
