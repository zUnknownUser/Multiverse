import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppStore.self) private var store

    /// A sheet reflete `logDraft` diretamente — qualquer tela pode abri-la chamando
    /// `store.openLog(for:)` / `openLogBlank()`, não só o botão + da tab bar.
    private var logSheetPresented: Binding<Bool> {
        Binding(get: { store.logDraft != nil }, set: { if !$0 { store.closeLog() } })
    }

    private var challengeSheetPresented: Binding<Bool> {
        Binding(get: { store.showingChallengeUserID != nil }, set: { if !$0 { store.showingChallengeUserID = nil } })
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch store.tab {
                case .home: HomeStack()
                case .search: SearchStack()
                case .library: LibraryStack()
                case .clubs: ClubsStack()
                case .profile: ProfileStack()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Reserve the bar's height outside the navigation stacks so pushed
            // screens can scroll their final actions fully above the bar.
            CustomTabBar { store.openLogBlank() }
        }
        .overlay { ToastOverlay() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.directMessages?.run()
        }
        .sheet(isPresented: logSheetPresented) {
            LogSheetView()
        }
        .sheet(isPresented: challengeSheetPresented) {
            if let userID = store.showingChallengeUserID {
                DuelChallengeSheet(userID: userID)
            }
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

private struct LibraryStack: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.libraryPath) {
            LibraryView().navigationDestination(for: Route.self) { RouteDestination(route: $0) }
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
    @Environment(AppStore.self) private var store
    var body: some View {
        if route.isDemonstration && !store.showsDemoFeatures { EmptyView() }
        else { destination }
    }
    @ViewBuilder private var destination: some View {
        switch route {
        case .item(let id): ItemView(itemID: id)
        case .catalogSeries(let id): CatalogSeriesView(seriesID: id)
        case .universe(let id): UniverseView(universeID: id)
        case .user(let id): ProfileView(userID: id)
        case .review(let id): ThreadView(reviewID: id)
        case .order(let id): ReadingOrderView(orderID: id)
        case .library: LibraryView()
        case .list(let id):
            if store.library != nil { PersonalListDetailView(listID: id) } else { ListDetailView(listID: id) }
        case .diary: DiaryView()
        case .wrapped: WrappedView()
        case .settings: SettingsView()
        case .blockedUsers: BlockedUsersView()
        case .deleteAccount: DeleteAccountView()
        case .community(let universe, let item): CommunityView(universe: universe, item: item)
        case .post(let id): PostView(id: id)
        case .dailyDuel(let id): DailyDuelView(id: id)
        case .communityFeed(let filter): CommunityView(universe: filter.universe, item: filter.item, initialFeed: filter.feed, initialSearch: filter.search, kind: filter.kind, club: filter.club, schedule: filter.schedule)
        case .liveClubs(let universe): LiveClubsView(universe: universe)
        case .liveClub(let id): LiveClubView(id: id)
        case .liveRooms(let universe): LiveRoomsView(universe: universe)
        case .liveRoom(let item): LiveRoomView(itemID: item)
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
        case .messages:
            if let dm = store.directMessages { DirectInboxView(messages: dm) }
            else if store.showsDemoFeatures { MessagesHomeView() }
        case .conversation(let id):
            if let dm = store.directMessages { DirectConversationView(thread: dm.thread(id), inbox: dm) }
            else if store.showsDemoFeatures { ConversationView(userID: id) }
        case .room(let id): ItemRoomView(itemID: id)
        case .exploreRooms: ExploreRoomsView()
        case .livePremiere: LivePremiereView()
        }
    }
}
