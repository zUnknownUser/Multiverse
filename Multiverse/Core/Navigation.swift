import Foundation

enum AppTab: String, CaseIterable, Hashable {
    case home, search, notifications, profile
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
}
