import SwiftUI

@main
struct YouthAISubsidyApp: App {
    init() {
        AppEnvironment.discardStaleConnectionSettings()
        if ProcessInfo.processInfo.arguments.contains("--ui-test-reset") {
            DemoCaseStore.shared.resetOwnCases()
            LocalAttachmentStore.removeAll()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Locale(identifier: "zh_TW"))
                .environment(\.font, .custom("PingFangTC-Regular", size: 17, relativeTo: .body))
        }
    }
}
