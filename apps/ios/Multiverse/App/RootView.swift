import SwiftUI
import GoogleSignIn

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppStore()
    @State private var auth = AuthStore()
    @State private var burst = BurstCenter()
    @State private var proStore = ProStore()
    @State private var pendingClub: String?
    @State private var pendingDuel: String?

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
            if let id = DuelInvitation.id(in: url.absoluteString) {
                pendingDuel = id; openDuelInvitation(); return
            }
            if url.scheme == "multiverse", url.host == "club", url.user == nil, url.password == nil, url.query == nil,
               let id = url.pathComponents.last, UUID(uuidString: id) != nil {
                pendingClub = id.lowercased(); openClubInvitation(); return
            }
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
                peopleAPI: api,
                socialAPI: api,
                communityAPI: api,
                notificationsAPI: api,
                libraryAPI: api,
                directMessagesAPI: api,
                readingOrdersAPI: api,
                dailyDuelsAPI: api,
                clubsAPI: api,
                roomsAPI: api,
                voiceAPI: api
            )
            store = accountStore
            await accountStore.bootstrap()
            if accountStore.isOnboarded {
                await accountStore.library?.refresh()
                await accountStore.notifications?.refresh()
                await PushCoordinator.shared.resume(api: api, userID: session.userID)
                openPushActivity()
                openClubInvitation()
                openDuelInvitation()
            }
        }
        .onChange(of: store.isOnboarded) { _, _ in openClubInvitation(); openDuelInvitation() }
        .onChange(of: PushCoordinator.shared.openActivity) { _, _ in openPushActivity() }
        .task(id: store.meID) {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                if scenePhase == .active && store.isOnboarded { await store.notifications?.refresh() }
            }
        }
        .task(id: badgeState) {
            guard !auth.isBootstrapping else { return }
            await AppBadgeCoordinator.shared.sync(userID: badgeState.userID, unreadCount: badgeState.count)
        }
        .task { await auth.bootstrap() }
        .task { await proStore.loadProducts() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await proStore.refreshEntitlement(); if store.isOnboarded { await store.notifications?.refresh(); await store.library?.refresh() } } }
        }

    }
    private struct BadgeState: Equatable {
        let bootstrapping: Bool
        let userID: String?
        let count: Int?
        let active: Bool
    }
    private var badgeState: BadgeState {
        let id = auth.session?.userID
        let count = id == store.meID && store.notifications?.hasLoaded == true ? store.notifications?.unreadCount : nil
        return BadgeState(bootstrapping: auth.isBootstrapping, userID: id, count: count, active: scenePhase == .active)
    }
    private func openDuelInvitation() {
        guard let id = pendingDuel, auth.session?.userID == store.meID, store.isOnboarded, !store.isLoading else { return }
        pendingDuel = nil; store.push(.dailyDuel(id))
    }
    private func openClubInvitation() {
        guard let id = pendingClub, auth.session?.userID == store.meID, store.isOnboarded, !store.isLoading else { return }
        pendingClub = nil; store.push(.liveClub(id))
    }
    private func openPushActivity() {
        guard PushCoordinator.shared.openActivity, auth.session?.userID == store.meID, store.isOnboarded else { return }
        PushCoordinator.shared.openActivity = false
        store.openNotifications()
    }
}

#Preview {
    RootView()
}
