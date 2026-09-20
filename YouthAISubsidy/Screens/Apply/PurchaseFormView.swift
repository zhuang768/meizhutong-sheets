import SwiftUI

struct PurchaseFormView: View {
    @Bindable var model: ApplicationFlowModel

    var body: some View {
        Form {
            ErrorSummary(issues: model.issues)
            Section("拍照／相簿帶入（選用）") {
                DocumentScanShortcut(type: .officialReceipt) { found in
                    if let tool = found.toolName { model.draft.purchase.toolName = tool }
                    if let vendor = found.vendorName { model.draft.purchase.vendorName = vendor }
                    if let date = found.purchaseDate { model.draft.purchase.purchaseDate = date }
                    if let amount = found.originalAmount { model.draft.purchase.originalAmount = DecimalString(amount) }
                    if let currency = found.currency { model.draft.purchase.originalCurrency = currency }
                    if let amount = found.twdAmount { model.draft.purchase.twdPaidAmount = DecimalString(amount) }
                    if found.isGeneratedSample {
                        model.attachSynthetic(.officialReceipt)
                    } else {
                        model.attachLocalPhoto(type: .officialReceipt, data: found.imageData)
                    }
                    model.banner = "已帶入辨識到的帳單欄位；憑證仍須自行核對，照片只存在手機內、尚未上傳。"
                }
            }
            Section("AI 工具與賣方") {
                Picker("功能類別", selection: $model.draft.purchase.toolCategory) {
                    ForEach(ToolCategory.allCases, id: \.self) { item in
                        Text(item.zhTitle).tag(item)
                    }
                }
                LabeledField(title: "完整 AI 名稱", hint: "須為完整產品名稱，不是工作區或空間名稱。") {
                    TextField("例如 Cursor", text: $model.draft.purchase.toolName)
                        .accessibilityIdentifier("purchase.toolName")
                }
                LabeledField(title: "軟體公司／賣方", hint: nil) {
                    TextField("例如 Anysphere", text: $model.draft.purchase.vendorName)
                        .accessibilityIdentifier("purchase.vendorName")
                }
                Toggle("確認非中國（含港澳）開發或營運", isOn: $model.draft.purchase.vendorRegionCompliant)
            }
            Section("購買管道與訂閱") {
                Picker("購買管道", selection: $model.draft.purchase.purchaseChannel) {
                    ForEach(PurchaseChannel.allCases, id: \.self) { item in
                        Text(item.zhTitle).tag(item)
                    }
                }
                Picker("訂閱方式", selection: $model.draft.purchase.subscriptionPlan) {
                    ForEach(SubscriptionPlan.allCases, id: \.self) { item in
                        Text(item.zhTitle).tag(item)
                    }
                }
                DatePicker("訂閱開始", selection: $model.draft.purchase.subscriptionStart, displayedComponents: .date)
                if model.draft.purchase.subscriptionPlan == .monthly {
                    Stepper("月費期數：\(model.draft.formFields.monthlyPeriods) 期", value: $model.draft.formFields.monthlyPeriods, in: 1...120)
                }
                DatePicker("訂閱結束或續訂日", selection: $model.draft.purchase.subscriptionEnd, displayedComponents: .date)
                DatePicker(
                    "購買日期",
                    selection: $model.draft.purchase.purchaseDate,
                    in: ROCDate.purchaseMin...ROCDate.purchaseMax,
                    displayedComponents: .date
                )
                Text("購買日：\(ROCDate.display(model.draft.purchase.purchaseDate))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                Toggle("此筆為預付儲值、Credit、點數、Token 或 API 額度", isOn: $model.draft.purchase.isPrepaidCreditOrToken)
            }
            Section("金額") {
                LabeledField(title: "原始費用", hint: "收據上的原始費用。") {
                    TextField("原始金額", value: originalAmountBinding, format: .number)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("purchase.originalAmount")
                }
                TextField("原始幣別", text: $model.draft.purchase.originalCurrency)
                    .accessibilityIdentifier("purchase.currency")
                LabeledField(title: "臺幣實付／帳單金額", hint: "補助以臺幣帳單金額為準。") {
                    TextField("臺幣金額", value: twdBinding, format: .number)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("purchase.twdPaid")
                }
                TextField("付款方式（勿填卡號）", text: $model.draft.purchase.paymentMethod)
                    .accessibilityIdentifier("purchase.paymentMethod")
            }
            Section("代付款") {
                Toggle("由父母、配偶或法定代理人代為付款", isOn: $model.draft.purchase.isProxyPaid)
                    .accessibilityIdentifier("purchase.proxyPaid")
                if model.draft.purchase.isProxyPaid {
                    TextField("代付人姓名", text: $model.draft.purchase.proxyPayerName)
                    TextField("關係", text: $model.draft.purchase.proxyPayerRelation)
                }
            }
            Section("購買憑證／發票一覽表") {
                Text("請逐項確認憑證內容。勾選僅為本人確認，不代表已通過審查。信用卡只呈現必要姓名、簽名及末四碼，遮蔽其他卡號與安全碼。")
                    .font(.footnote)
                ForEach(ApplicationFormFields.receiptItems, id: \.id) { item in
                    Toggle(item.title, isOn: Binding(
                        get: { model.draft.formFields.receiptConfirmations.contains(item.id) },
                        set: { checked in
                            if checked { model.draft.formFields.receiptConfirmations.insert(item.id) }
                            else { model.draft.formFields.receiptConfirmations.remove(item.id) }
                        }
                    ))
                }
            }
            Section {
                EstimateCard(estimate: model.estimate)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var originalAmountBinding: Binding<Double> {
        Binding(
            get: { NSDecimalNumber(decimal: model.draft.purchase.originalAmount.value).doubleValue },
            set: { model.draft.purchase.originalAmount = DecimalString(Decimal($0)) }
        )
    }

    private var twdBinding: Binding<Double> {
        Binding(
            get: { NSDecimalNumber(decimal: model.draft.purchase.twdPaidAmount.value).doubleValue },
            set: { model.draft.purchase.twdPaidAmount = DecimalString(Decimal($0)) }
        )
    }
}
