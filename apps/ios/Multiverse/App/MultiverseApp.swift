import SwiftUI
import FirebaseCore
import FirebaseAnalytics
import FirebaseAppCheck

@main
struct MultiverseApp: App {
    init() {
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(MultiverseAppCheckProviderFactory())
        #endif
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
