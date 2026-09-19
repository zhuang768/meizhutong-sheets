import SwiftUI

struct CaseListView: View {
    @Environment(ApplicationFlowModel.self) private var model

    var body: some View {
        List {
            Section {
                DemoBanner()
                    .listRowInsets(EdgeInsets())
            }
            Section("我的案件") {
                if model.ownCases.isEmpty {
                    Text("尚無自己的申請。填寫後可在此查看手機內記錄的狀態；合成案例在「說明」頁。")
                        .foregroundStyle(AppTheme.muted)
                        .accessibilityIdentifier("cases.emptyOwn")
                }
                ForEach(model.ownCases) { item in
                    NavigationLink(value: item) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.applicant.fullName.isEmpty ? "未填姓名" : item.applicant.fullName)
                                .font(.headline)
                                .accessibilityIdentifier("cases.name.\(item.caseId)")
                            Text(YouthPresentation.displayCaseId(item.caseId))
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                                .accessibilityIdentifier("cases.id.\(item.caseId)")
                            HStack {
                                StatusBadge(status: item.status)
                                Text(item.purchase.toolName)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("cases.row.\(item.caseId)")
                }
            }
        }
        .navigationTitle("我的案件")
        .navigationDestination(for: SubsidyCase.self) { item in
            CaseStatusView(item: item, isDemoFixture: YouthPresentation.isFixtureCaseId(item.caseId))
        }
        .refreshable {
            await model.refreshCases()
        }
        .task {
            await model.refreshCases()
        }
    }
}

struct CaseStatusView: View {
    @Environment(ApplicationFlowModel.self) private var model
    let item: SubsidyCase
    var isDemoFixture = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DemoBanner()
                if isDemoFixture {
                    Text("這是合成測試案例，不是你的申請。")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.warning)
                        .accessibilityIdentifier("status.demoFixture")
                }
                HStack {
                    Text(YouthPresentation.displayCaseId(item.caseId))
                        .font(.headline)
                    Spacer()
                    StatusBadge(status: item.status)
                }
                .accessibilityIdentifier("status.caseId")
                if let note = item.publicStatusNote, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink)
                        .accessibilityIdentifier("status.publicNote")
                }
                if item.status == .draft && !isDemoFixture {
                    Button("繼續填寫草稿") { model.resumeDraft(item) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("status.resumeDraft")
                }
                if item.status.isTerminalDecision {
                    Text("此核准或駁回若出現，只能來自後端人工結果，不是 App 自行產生。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.warning)
                }
                EstimateCard(estimate: SubsidyEstimator.estimate(for: item))
                VStack(alignment: .leading, spacing: 8) {
                    supplementSection(for: item)
                }
                .padding(16)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
        }
        .background(AppTheme.background)
        .navigationTitle("案件狀態")
    }

    @ViewBuilder
    private func supplementSection(for item: SubsidyCase) -> some View {
        switch YouthPresentation.supplementDisplay(for: item) {
        case .syntheticDemo(let messages):
            Text("合成補件示範")
                .font(.headline)
                .accessibilityIdentifier("status.supplement")
            Text("非正式承辦通知，也不是內部預檢結果。")
                .font(.caption)
                .foregroundStyle(AppTheme.warning)
            ForEach(messages, id: \.self) { message in
                Text("• \(message)")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.warning)
            }
        case .awaitingOfficialExplanation:
            Text("補件通知")
                .font(.headline)
                .accessibilityIdentifier("status.supplement")
            Text("案件已標為需補件，但對外補件說明仍待後端契約確認，不會顯示內部預檢缺件。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
        case .none:
            Text("補件通知")
                .font(.headline)
                .accessibilityIdentifier("status.supplement")
            Text("目前沒有承辦發出的補件通知。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .accessibilityIdentifier("status.noOfficialSupplement")
        }
    }
}
