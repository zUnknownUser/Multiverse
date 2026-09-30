import SwiftUI
import GoogleSignIn

struct RootView: View {
    @State private var store = AppStore()
    @State private var auth = AuthStore()
    @State private var burst = BurstCenter()
    @State private var proStore = ProStore()

    var body: some View {
        Group {
            if auth.isBootstrapping {
                LaunchLoadingView()
            } else if auth.session == nil || auth.path.last == .newPassword {
                AuthFlowView()
            } else if store.isLoading || store.meID != auth.session?.userID {
                LaunchLoadingView()
            } else if store.isOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .alert(auth.errorMessage != nil ? "Não foi possível continuar" : "Multiverse", isPresented: Binding(
            get: { auth.errorMessage != nil || auth.infoMessage != nil },
            set: { if !$0 { auth.errorMessage = nil; auth.infoMessage = nil } }
        )) {
            Button("OK") { auth.errorMessage = nil; auth.infoMessage = nil }
        } message: {
            Text(auth.errorMessage ?? auth.infoMessage ?? "")
        }
        .onOpenURL { url in
            if !GIDSignIn.sharedInstance.handle(url) { Task { await auth.handleEmailLink(url) } }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { Task { await auth.handleEmailLink(url) } }
        }
        .environment(store)
        .environment(auth)
        .environment(burst)
        .environment(proStore)
        .preferredColorScheme(store.themePreference.colorScheme)
        .task(id: auth.session) {
            guard let session = auth.session else {
                store = AppStore()
                return
            }
            let accountStore = AppStore(session: session)
            store = accountStore
            await accountStore.bootstrap()
        }
        .task { await auth.bootstrap() }
        .task { await proStore.loadProducts() }

    }
}

#Preview {
    RootView()
}
