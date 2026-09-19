import SwiftUI

struct DemoSandboxView: View {
    @Environment(ApplicationFlowModel.self) private var model
    @State private var showResetConfirmation = false
    @AppStorage("syntheticLinkBaseURL") private var linkBaseURL = "http://127.0.0.1:8791"
    @State private var linked: SyntheticLinkClient.Link?
    @State private var linkedStatus = ""
    @State private var linkMessage = ""
    @State private var linking = false

    var body: some View {
        List {
            Section {
                Text("此區只放合成測試資料。三筆驗收案例不會出現在「案件」分頁，也不能當成你自己的申請。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                    .accessibilityIdentifier("demo.sandboxNotice")
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
            Section("與承辦工作台連動測試") {
                Text("只傳目前申請頁的合成欄位與合成附件種類，不傳影像、身分證字號或手機裡的真實案件。後端重新啟動後，這筆測試案件會消失。")
                    .font(.footnote)
                TextField("Mac 測試網址", text: $linkBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityIdentifier("syntheticLink.baseURL")
                Button("將目前合成申請送到承辦工作台") {
                    Task { await sendSyntheticApplication() }
                }
                .disabled(linking)
                .accessibilityIdentifier("syntheticLink.submit")
                if let linked {
                    Text("案件編號：\(linked.case.caseId)")
                        .textSelection(.enabled)
                    Text("後端狀態：\(linkedStatus)")
                    Button("更新承辦處理狀態") {
                        Task { await refreshLinkedStatus() }
                    }
                    .disabled(linking)
                    .accessibilityIdentifier("syntheticLink.refresh")
                }
                if !linkMessage.isEmpty {
                    Text(linkMessage).font(.footnote)
                        .accessibilityIdentifier("syntheticLink.feedback")
                }
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
        .confirmationDialog("清除這支手機的申請資料與附件？", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("清除申請資料", role: .destructive) {
                Task { await model.resetOwnDemoCases() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func templateButton(_ title: String, id: String) -> some View {
        Button(title) {
            model.loadTemplate(id, attachingSyntheticDocuments: false)
        }
    }

    private func sendSyntheticApplication() async {
        linking = true
        defer { linking = false }
        do {
            let result = try await SyntheticLinkClient.submit(model.draft, to: linkBaseURL)
            linked = result
            linkedStatus = result.case.status
            linkMessage = "承辦工作台已可查詢這筆合成案件。"
        } catch {
            linkMessage = error.localizedDescription
        }
    }

    private func refreshLinkedStatus() async {
        guard let linked else { return }
        linking = true
        defer { linking = false }
        do {
            let result = try await SyntheticLinkClient.refresh(linked, at: linkBaseURL)
            linkedStatus = result.status
            linkMessage = result.statusNote ?? "已讀取後端最新狀態。"
        } catch {
            linkMessage = error.localizedDescription
        }
    }
}

extension ApplicationFlowModel {
    var demoFixtures: [SubsidyCase] {
        DemoCaseStore.shared.listDemoFixtures()
    }
}
