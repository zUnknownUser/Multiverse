import SwiftUI

struct MainTabView: View {
    @Environment(AppStore.self) private var store

    /// A sheet reflete `logDraft` diretamente — qualquer tela pode abri-la chamando
    /// `store.openLog(for:)` / `openLogBlank()`, não só o botão + da tab bar.
    private var logSheetPresented: Binding<Bool> {
        Binding(get: { store.logDraft != nil }, set: { if !$0 { store.closeLog() } })
    }

    var body: some View {
        Group {
            switch store.tab {
            case .home: HomeStack()
            case .search: SearchStack()
            case .clubs: ClubsStack()
            case .profile: ProfileStack()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar { store.openLogBlank() }
        }
        .overlay { ToastOverlay() }
        .sheet(isPresented: logSheetPresented) {
            LogSheetView()
        }
    }
}

private struct HomeStack: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.homePath) {
            HomeView()
                .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
        }
    }
}

private struct SearchStack: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.searchPath) {
            SearchView()
                .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
        }
    }
}

private struct ClubsStack: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.clubsPath) {
            ClubsHomeView()
                .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
        }
    }
}

private struct ProfileStack: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.profilePath) {
            ProfileView(userID: store.meID)
                .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
        }
    }
}

/// Resolve cada `Route` empilhada pra sua tela correspondente.
private struct RouteDestination: View {
    let route: Route
    var body: some View {
        switch route {
        case .item(let id): ItemView(itemID: id)
        case .universe(let id): UniverseView(universeID: id)
        case .user(let id): ProfileView(userID: id)
        case .review(let id): ThreadView(reviewID: id)
        case .order(let id): ReadingOrderView(orderID: id)
        case .list(let id): ListDetailView(listID: id)
        case .diary: DiaryView()
        case .wrapped: WrappedView()
        case .settings: SettingsView()
        case .blockedUsers: BlockedUsersView()
        case .deleteAccount: DeleteAccountView()
        case .notifications: NotificationsView()
        case .club(let id): ClubDetailView(clubID: id)
        case .clubDiscussion(let clubID, let week): ClubDiscussionView(clubID: clubID, week: week)
        case .theories: TheoriesFeedView()
        case .theoryDetail(let id): TheoryDetailView(theoryID: id)
        case .predictions: PredictionsView()
        case .correctionForm(let itemID): SuggestCorrectionView(itemID: itemID)
        case .pro: ProPaywallView()
        case .proStats: ProStatsView()
        case .adjustShieldPoint: AdjustShieldPointView()
        }
    }
}
