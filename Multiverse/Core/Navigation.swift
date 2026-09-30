import Foundation

enum AppTab: String, CaseIterable, Hashable {
    case home, search, clubs, profile
}

/// Destinos navegáveis dentro da NavigationStack de cada aba.
enum Route: Hashable {
    case item(String)
    case universe(String)
    case user(String)
    case review(String)
    case order(String)
    case list(String)
    case diary
    case wrapped
    case settings
    case blockedUsers
    case deleteAccount
    /// Avisos deixou de ser aba — agora é o sino no topo da Home, empilhado como rota.
    case notifications
    case club(String)
    case clubDiscussion(clubID: String, week: Int)
    case theories
    case theoryDetail(String)
    case predictions
    case correctionForm(String)
    case pro
    case proStats
    case adjustShieldPoint
    case messages
    case conversation(String)
    case room(String)
    case exploreRooms
    case livePremiere
}
