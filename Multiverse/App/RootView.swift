import SwiftUI

struct RootView: View {
    @State private var store = AppStore()
    @State private var auth = AuthStore()
    @State private var burst = BurstCenter()
    @State private var proStore = ProStore()

    var body: some View {
        Group {
            if store.isLoading || auth.isBootstrapping {
                LaunchLoadingView()
            } else if auth.session == nil {
                AuthFlowView()
            } else if store.isOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .environment(store)
        .environment(auth)
        .environment(burst)
        .environment(proStore)
        .preferredColorScheme(store.themePreference.colorScheme)
        .task { await store.bootstrap() }
        .task { await auth.bootstrap() }
        .task { await proStore.loadProducts() }
        .onChange(of: auth.session) { _, newSession in
            guard newSession != nil, !auth.draft.name.isEmpty else { return }
            store.applyProfileEdits(name: auth.draft.name, handle: auth.draft.username.hasPrefix("@") ? auth.draft.username : "@\(auth.draft.username)", avatarColor: auth.draft.avatarColor, bio: auth.draft.bio)
        }
    }
}

#Preview {
    RootView()
}
