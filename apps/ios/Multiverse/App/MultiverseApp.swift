import SwiftUI
import FirebaseCore
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
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path),
              options.projectID == AppEnvironment.current.firebaseProjectID,
              options.bundleID == AppEnvironment.current.bundleID else { preconditionFailure("Firebase deployment configuration mismatch") }
        FirebaseApp.configure(options: options)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
