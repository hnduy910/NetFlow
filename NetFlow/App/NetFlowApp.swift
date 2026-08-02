import SwiftUI

@main
struct NetFlowApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environment(\.locale, store.settings.appLanguage.locale)
                .preferredColorScheme(store.settings.theme.colorScheme)
                .task { await store.start() }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                Task { await store.refreshAfterBecomingActive() }
            case .background:
                store.pauseSampling()
            case .inactive:
                store.save()
            @unknown default:
                break
            }
        }
    }
}
