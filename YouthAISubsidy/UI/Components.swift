import SwiftUI

struct DemoBanner: View {
    var text: String = AppEnvironment.connectionLabel

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.subtleFill)
            .accessibilityIdentifier("demo.banner")
            .accessibilityAddTraits(.isStaticText)
    }
}

struct PrototypeDisclaimer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("競賽原型，非正式市府申辦入口")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text("申請人仍須完整填寫官方要求資料並上傳所有適用文件。本 App 不刪減必填項，也不自行產生核准或駁回。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.primary.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ErrorSummary: View {
    let issues: [ValidationIssue]

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("尚未填齊")
                    .font(.headline)
                    .foregroundStyle(AppTheme.danger)
                ForEach(issues) { issue in
                    Text("• \(issue.message)")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.dangerFill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("form.errorSummary")
        }
    }
}

struct EstimateCard: View {
    let estimate: SubsidyEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("預估補助 \(estimate.amount.displayInt) 元")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Text("非核定金額")
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.subtleFill)
                .clipShape(Capsule())
                .accessibilityIdentifier("estimate.unofficial")
            ForEach(estimate.hints, id: \.self) { hint in
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StatusBadge: View {
    let status: CaseStatus

    var body: some View {
        Text(status.zhTitle)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityLabel(status.zhTitle)
    }

    private var color: Color {
        switch status {
        case .draft: return AppTheme.muted
        case .submitted: return AppTheme.primary
        case .needsDocuments: return AppTheme.warning
        case .underManualReview: return AppTheme.primary
        case .approved: return AppTheme.accent
        case .rejected: return AppTheme.danger
        }
    }
}

struct WizardFooter: View {
    let canGoBack: Bool
    let primaryTitle: String
    let step: WizardStep
    let isBusy: Bool
    let onBack: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if canGoBack {
                Button("上一步", action: onBack)
                    .disabled(isBusy)
                    .frame(minHeight: AppTheme.minTouch)
                    .accessibilityIdentifier("wizard.back")
            }
            Button(action: onPrimary) {
                if isBusy {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTouch)
                } else {
                    Text(primaryTitle)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTouch)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.wizardAccent(for: step))
            .animation(.easeInOut(duration: 0.3), value: step)
            .disabled(isBusy)
            .accessibilityIdentifier("wizard.primary")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

struct LabeledField<Content: View>: View {
    let title: String
    let hint: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            content()
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
