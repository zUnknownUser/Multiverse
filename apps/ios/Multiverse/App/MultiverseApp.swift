import SwiftUI
import FirebaseCore
import FirebaseAnalytics
import FirebaseAppCheck

@main
struct MultiverseApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
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
