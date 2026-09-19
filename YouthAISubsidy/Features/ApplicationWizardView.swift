import SwiftUI
import UIKit

struct ApplicationWizardView: View {
    @Environment(ApplicationFlowModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            DemoBanner(text: model.isDemoMode ? "資料僅存這支手機・尚未送市府" : "團隊測試收件服務・非市府正式申辦")
            if let banner = model.banner {
                Text(banner)
                    .font(.footnote)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.card)
                    .accessibilityIdentifier("wizard.feedback")
            }
            Group {
                switch model.step {
                case .applicant:
                    ApplicantFormView(model: model)
                case .purchase:
                    PurchaseFormView(model: model)
                case .documents:
                    DocumentsView(model: model)
                case .awareness:
                    AwarenessView()
                case .review:
                    ReviewSubmitView(model: model)
                }
            }
        }
        .background(AppTheme.background)
        .navigationTitle(model.step.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            WizardFooter(
                canGoBack: model.step != .applicant && model.lastSubmittedId == nil,
                primaryTitle: primaryTitle,
                step: model.step,
                isBusy: model.isBusy || model.isImportingAttachment,
                onBack: { model.goBack() },
                onPrimary: { handlePrimary() }
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.lastSubmittedId == nil {
                Button("存草稿") {
                    Task { await model.saveDraft() }
                }
                .disabled(model.isBusy || model.isImportingAttachment)
                .accessibilityIdentifier("wizard.saveDraft")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                if model.isEditingFromSummary {
                    Button("返回摘要") { model.returnToSummary() }
                        .disabled(model.isBusy || model.isImportingAttachment)
                        .accessibilityIdentifier("wizard.returnToSummary")
                } else if model.lastSubmittedId == nil {
                    Button("填入測試資料") { model.fillTestApplication() }
                        .disabled(model.isBusy || model.isImportingAttachment)
                        .accessibilityIdentifier("wizard.fillTest")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .accessibilityIdentifier("keyboard.dismiss")
            }
        }
    }

    private var primaryTitle: String {
        if model.lastSubmittedId != nil { return "查看我的申請" }
        return model.step == .review ? "確認送出" : "下一步"
    }

    private func handlePrimary() {
        if model.lastSubmittedId != nil {
            model.selectedTab = .cases
        } else if model.step == .review {
            Task { await model.submit() }
        } else {
            model.goNext()
        }
    }
}
