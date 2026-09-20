import SwiftUI

struct ReviewSubmitView: View {
    @Bindable var model: ApplicationFlowModel

    var body: some View {
        Form {
            if let id = model.lastSubmittedId {
                Section("送出結果") {
                    Text("手機內編號：\(YouthPresentation.displayCaseId(id))")
                        .font(.headline)
                        .accessibilityIdentifier("review.submittedId")
                    Text(model.isDemoMode ? "已在這支手機記錄申請，尚未送交市府。" : "試算表收件服務已收妥申請與附件；非市府正式收件。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            ErrorSummary(issues: model.issues)
            Section {
                DemoBanner()
                PrototypeDisclaimer()
                EstimateCard(estimate: model.estimate)
            }
            Section("申請人") {
                editButton("修改申請人資料", step: .applicant)
                row("姓名", model.draft.applicant.fullName)
                row("出生", ROCDate.display(model.draft.applicant.birthDate))
                row("設籍新竹市", model.draft.applicant.isHsinchuResident ? "是" : "否")
                row("地址", model.draft.applicant.householdAddress)
                row("電子信箱", model.draft.applicant.contactEmail)
                row("電話", model.draft.applicant.phone)
                row("身分證字號", model.draft.formFields.nationalID.isEmpty ? "未填" : "已填寫（隱藏顯示）")
                row("戶籍郵遞區號／行政區", "\(model.draft.formFields.householdPostalCode) \(model.draft.formFields.householdDistrict)")
                row("通訊地址", model.draft.formFields.mailingSameAsHousehold ? model.draft.applicant.householdAddress : "\(model.draft.formFields.mailingPostalCode) \(model.draft.formFields.mailingCity)\(model.draft.formFields.mailingDistrict)\(model.draft.formFields.mailingStreet)")
                row("身分類別", model.draft.applicant.identityCategory.zhTitle)
                if !model.draft.applicant.specialIdentityKinds.isEmpty {
                    row("特定對象", model.draft.applicant.specialIdentityKinds.map(\.zhTitle).joined(separator: "、"))
                }
                if !model.draft.applicant.culturalLanguageKinds.isEmpty {
                    row("語言證照", model.draft.applicant.culturalLanguageKinds.map(\.zhTitle).joined(separator: "、"))
                }
                row("金融機構", model.draft.applicant.bankName)
                row("帳戶對照", model.draft.applicant.bankAccountMasked)
            }
            Section("AI 工具與購買") {
                editButton("修改購買資料", step: .purchase)
                row("類別", model.draft.purchase.toolCategory.zhTitle)
                row("工具", model.draft.purchase.toolName)
                row("賣方", model.draft.purchase.vendorName)
                row("非中國含港澳", model.draft.purchase.vendorRegionCompliant ? "是" : "否")
                row("管道", model.draft.purchase.purchaseChannel.zhTitle)
                row("訂閱", model.draft.purchase.subscriptionPlan.zhTitle)
                if model.draft.purchase.subscriptionPlan == .monthly {
                    row("月費期數", "\(model.draft.formFields.monthlyPeriods) 期")
                }
                row("購買憑證確認", "\(model.draft.formFields.receiptConfirmations.count)／8 項")
                row("訂閱期間", "\(ROCDate.display(model.draft.purchase.subscriptionStart)) 至 \(ROCDate.display(model.draft.purchase.subscriptionEnd))")
                row("購買日", ROCDate.display(model.draft.purchase.purchaseDate))
                row("原始金額", "\(model.draft.purchase.originalAmount.displayTWD) \(model.draft.purchase.originalCurrency)")
                row("臺幣實付", "\(model.draft.purchase.twdPaidAmount.displayTWD) TWD")
                row("付款方式", model.draft.purchase.paymentMethod)
                row("預付額度", model.draft.purchase.isPrepaidCreditOrToken ? "是（不可補助）" : "否")
                row("代付", model.draft.purchase.isProxyPaid ? "\(model.draft.purchase.proxyPayerRelation)／\(model.draft.purchase.proxyPayerName)" : "否")
            }
            Section("文件") {
                editButton("修改附件", step: .documents)
                ForEach(FormValidator.requiredDocumentTypes(for: model.draft), id: \.self) { type in
                    let attached = model.draft.documents.first(where: { $0.type == type })
                    row(type.zhTitle, YouthPresentation.attachmentStatusText(for: attached))
                }
            }
            Section("確認") {
                Text("送出後狀態只會成為「已送出」或由後端回傳的補件／審查狀態。本 App 不會產生核准或駁回，也不會把本機附件標成已上傳。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                if let banner = model.banner {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink)
                        .accessibilityIdentifier("review.resultBanner")
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
            Text(value)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func editButton(_ title: String, step: WizardStep) -> some View {
        if model.lastSubmittedId == nil {
            Button(title) { model.editFromSummary(step) }
                .accessibilityIdentifier("review.edit.\(step.rawValue)")
        }
    }
}
