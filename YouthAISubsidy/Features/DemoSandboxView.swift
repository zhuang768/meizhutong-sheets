import SwiftUI

struct DemoSandboxView: View {
    @Environment(ApplicationFlowModel.self) private var model
    @State private var showResetConfirmation = false

    var body: some View {
        List {
            Section {
                Text("此區只放合成測試資料。三筆驗收案例不會出現在「案件」分頁，也不能當成你自己的申請。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                    .accessibilityIdentifier("demo.sandboxNotice")
            }
            Section("送到試算表（Excel 第 1–20 筆）") {
                Text("與桌面 Excel 前 20 筆同一組合成情境。按一下會走正式送件契約寫入試算表，並附合成身分證、發票與切結書；其中 3 筆影像刻意不符，方便 GPT 查核。App 不會核准或駁回。未連接收件服務時不會假裝已送出。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                Text("已送出 \(model.spreadsheetBatchSubmittedCount) / \(SyntheticLoadTest.importCap) 筆")
                    .accessibilityIdentifier("loadtest.progress")
                Button("送出 Excel 第 1–20 筆到試算表") {
                    Task { await model.submitSpreadsheetBatch() }
                }
                .disabled(loadTestBusy || model.spreadsheetBatchSubmittedCount >= SyntheticLoadTest.importCap)
                .accessibilityIdentifier("loadtest.submitBatch")
                if model.isSubmittingSpreadsheetBatch {
                    ProgressView()
                }
            }
            Section("載入欄位到填寫流程") {
                templateButton("案例 1：一般青年／Cursor 年費", id: SyntheticFixtures.generalId)
                    .accessibilityIdentifier("demo.loadGeneral")
                Button("案例 1 載入並附齊合成文件") {
                    model.loadTemplate(SyntheticFixtures.generalId, attachingSyntheticDocuments: true)
                }
                .accessibilityIdentifier("demo.loadGeneralReady")
                templateButton("案例 2：特定對象／ChatGPT 月費", id: SyntheticFixtures.specialId)
                    .accessibilityIdentifier("demo.loadSpecial")
                templateButton("案例 3：父母代付／Claude 年費", id: SyntheticFixtures.proxyId)
                    .accessibilityIdentifier("demo.loadProxy")
            }
            Section("查看合成案件狀態（非正式）") {
                ForEach(model.demoFixtures) { item in
                    NavigationLink {
                        CaseStatusView(item: item, isDemoFixture: true)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.applicant.fullName)
                                .font(.headline)
                            Text(YouthPresentation.displayCaseId(item.caseId))
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                            HStack {
                                StatusBadge(status: item.status)
                                Text("合成案例")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.warning)
                            }
                        }
                    }
                    .accessibilityIdentifier("demo.fixture.\(item.caseId)")
                }
            }
            Section {
                Button("清除這支手機的申請資料") {
                    showResetConfirmation = true
                }
                .accessibilityIdentifier("demo.resetOwnCases")
            }
            if let banner = model.banner {
                Section { Text(banner).accessibilityIdentifier("demo.feedback") }
            }
        }
        .navigationTitle("合成測試")
        .task { model.loadSpreadsheetBatchProgress() }
        .confirmationDialog("清除這支手機的申請資料與附件？", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("清除申請資料", role: .destructive) {
                Task { await model.resetOwnDemoCases() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var loadTestBusy: Bool {
        model.isSubmittingSpreadsheetBatch || model.isBusy || model.isImportingAttachment
    }

    private func templateButton(_ title: String, id: String) -> some View {
        Button(title) {
            model.loadTemplate(id, attachingSyntheticDocuments: false)
        }
    }
}

extension ApplicationFlowModel {
    var demoFixtures: [SubsidyCase] {
        DemoCaseStore.shared.listDemoFixtures()
    }
}
