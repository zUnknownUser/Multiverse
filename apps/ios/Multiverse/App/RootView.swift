import SwiftUI
import GoogleSignIn

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppStore()
    @State private var auth = AuthStore()
    @State private var burst = BurstCenter()
    @State private var proStore = ProStore()

    var body: some View {
        Group {
            if auth.isBootstrapping {
                LaunchLoadingView()
            } else if auth.session == nil || auth.session?.needsProfile == true || auth.path.last == .newPassword {
                AuthFlowView()
            } else if store.isLoading || store.meID != auth.session?.userID {
                LaunchLoadingView()
            } else if let issue = store.catalogIssue {
                DataLoadStatusView(title: issue.title, message: issue.errorDescription ?? "",
                                  retryTitle: issue == .empty ? L10n.text("VERIFICAR NOVAMENTE") : L10n.text("TENTAR DE NOVO"), isSigningOut: auth.isLoading,
                                  retry: { Task { await store.reloadAccount() } },
                                  signOut: { Task { await auth.signOut() } })
            } else if let error = store.activityLoadError {
                DataLoadStatusView(title: L10n.text("Não conseguimos carregar seu diário"), message: error, isSigningOut: auth.isLoading,
                                  retry: { Task { await store.reloadAccount() } },
                                  signOut: { Task { await auth.signOut() } })
            } else if store.accountLoadError != nil {
                LaunchLoadingView()
            } else if store.isOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .alert(auth.errorMessage != nil || store.accountLoadError != nil || store.onboardingError != nil ? L10n.text("Não foi possível continuar") : "Multiverse", isPresented: Binding(
            get: { auth.errorMessage != nil || auth.infoMessage != nil || store.accountLoadError != nil || store.onboardingError != nil },
            set: { if !$0 { auth.errorMessage = nil; auth.infoMessage = nil } }
        )) {
            if auth.bootstrapFailed {
                Button(L10n.text("TENTAR DE NOVO")) { Task { await auth.bootstrap() } }
                Button(L10n.text("SAIR"), role: .cancel) { Task { await auth.signOut() } }
            } else if store.accountLoadError != nil || store.onboardingError != nil {
                Button(L10n.text("TENTAR DE NOVO")) { Task { await store.reloadAccount() } }
                Button(L10n.text("SAIR"), role: .cancel) { Task { await auth.signOut() } }
            } else {
                Button("OK") { auth.errorMessage = nil; auth.infoMessage = nil }
            }
        } message: {
            Text(auth.errorMessage ?? auth.infoMessage ?? store.accountLoadError ?? store.onboardingError ?? "")
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
            guard let session = auth.session, !session.needsProfile else {
                WidgetBridge.clear()
                store = AppStore()
                return
            }
            let api = AccountAPIClient(expectedUserID: session.userID)
            let accountStore = AppStore(
                session: session,
                accountAPI: api,
                widgetWriter: WidgetBridge.beginSession(),
                catalogAPI: CatalogAPIClient(),
                activityAPI: api,
                peopleAPI: api
            )
            store = accountStore
            await accountStore.bootstrap()
        }
        .task { await auth.bootstrap() }
        .task { await proStore.loadProducts() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await proStore.refreshEntitlement() } }
        }

    }
}

#Preview {
    RootView()
}
