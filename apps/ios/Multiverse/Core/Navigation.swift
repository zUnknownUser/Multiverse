import Foundation

enum AppTab: String, CaseIterable, Hashable {
    case home, search, library, clubs, profile
}

/// Destinos navegáveis dentro da NavigationStack de cada aba.
enum Route: Hashable {
    case item(String)
    case catalogSeries(String)
    case universe(String)
    case user(String)
    case review(String, comment: String? = nil)
    case order(String)
    case list(String)
    case library
    case diary
    case wrapped
    case settings
    case legal(LegalDocumentKind)
    case blockedUsers
    case deleteAccount
    /// Avisos deixou de ser aba — agora é o sino no topo da Home, empilhado como rota.
    case community(universe: String?, item: String?)
    case post(String, comment: String? = nil)
    case dailyDuel(String)
    case communityFeed(CommunityFilter)
    case liveClubs(String?)
    case liveClub(String)
    case liveRooms(String?)
    case liveRoom(String)
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

extension Route {
    var isDemonstration: Bool {
        switch self {
        case .wrapped, .club, .clubDiscussion, .theories, .theoryDetail, .predictions, .correctionForm, .adjustShieldPoint, .room, .exploreRooms, .livePremiere, .pro: true
        default: false
        }
    }
}

// Notification destinations preserve the exact response without replacing the
// current stack, so Back returns to the same loaded notification list.
extension ActivityNotification {
    var destination: Route? {
        switch targetType {
        case "message": .conversation(user)
        case "review": .review(targetID, comment: commentID)
        case "post": .post(targetID, comment: commentID)
        case "person": .user(targetID)
        default: nil
        }
    }
}

extension AppStore {
    func openNotification(_ entry: ActivityNotification) async {
        guard let destination = entry.destination else { return }
        let current: Route? = switch tab {
        case .home: homePath.last
        case .search: searchPath.last
        case .library: libraryPath.last
        case .clubs: clubsPath.last
        case .profile: profilePath.last
        }
        if current != destination { push(destination) }
        // A failed receipt preserves the badge and never prevents navigation.
        _ = await notifications?.markRead([entry.id])
    }
}
