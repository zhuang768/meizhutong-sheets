import SwiftUI

struct RootView: View {
    @State private var model = ApplicationFlowModel()
    @State private var casePath: [SubsidyCase] = []

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("申請", systemImage: "square.and.pencil") }
            .tag(AppTab.home)

            NavigationStack {
                ApplicationWizardView()
            }
            .tabItem { Label("填寫", systemImage: "list.bullet.clipboard") }
            .tag(AppTab.application)

            NavigationStack(path: $casePath) {
                CaseListView()
            }
            .tabItem { Label("案件", systemImage: "folder") }
            .tag(AppTab.cases)

            NavigationStack {
                AboutView()
            }
            .tabItem { Label("說明", systemImage: "info.circle") }
            .tag(AppTab.about)
        }
        .tint(AppTheme.primary)
        .environment(model)
        .onChange(of: model.selectedTab) { _, tab in
            if tab == .cases { casePath = [] }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--ui-test-autoload-general") {
                model.loadTemplate(SyntheticFixtures.generalId, attachingSyntheticDocuments: true)
            }
            await model.refreshCases()
        }
    }
}

#Preview {
    RootView()
}
