import Foundation

struct DailyDuelRound: Decodable, Identifiable, Sendable {
    let id: String
    let day: String
    let opensAt: Date
    let closesAt: Date
    let universeID: String
    let title: String
    let text: String
    let optionA: String
    let optionB: String
    let votes: PostVotes
    let commentCount: Int
    var totalVotes: Int { votes.counts.reduce(0, +) }
    func validate() throws {
        guard UUID(uuidString: id) != nil, ["marvel", "dc"].contains(universeID), !title.isEmpty,
              !optionA.isEmpty, !optionB.isEmpty, optionA != optionB, closesAt > opensAt,
              votes.counts.count == 2, votes.counts.allSatisfy({ $0 >= 0 && $0 <= 1_000_000_000 }),
              votes.mine == nil || [0,1].contains(votes.mine!), commentCount >= 0 else { throw SocialError.invalid }
    }
}
struct DuelProgress: Decodable, Sendable {
    let rounds: Int
    let monthlyPoints: Int
    let streak: Int
    var title: String {
        if rounds >= 100 { return L10n.text("LENDA DA ARENA") }
        if rounds >= 30 { return L10n.text("VETERANO DA ARENA") }
        if rounds >= 7 { return L10n.text("DEFENSOR DA ARENA") }
        if rounds >= 1 { return L10n.text("ESTREANTE DA ARENA") }
        return L10n.text("SUA JORNADA COMEÇA AQUI")
    }
    var nextMilestone: Int? { [1,7,30,100].first { $0 > rounds } }
    func validate() throws {
        guard rounds >= 0, streak >= 0, streak <= rounds, monthlyPoints >= 0, monthlyPoints <= 310, monthlyPoints % 10 == 0 else { throw SocialError.invalid }
    }
}
struct DailyDuelHub: Decodable, Sendable {
    let serverTime: Date
    let today: DailyDuelRound?
    let previous: DailyDuelRound?
    let progress: DuelProgress
    func validate() throws {
        try today?.validate(); try previous?.validate(); try progress.validate()
        guard today?.id != previous?.id || today == nil,
              previous.map({ $0.closesAt <= serverTime }) ?? true else { throw SocialError.invalid }
    }
}
struct DailyDuelDetail: Decodable, Sendable {
    let serverTime: Date
    let round: DailyDuelRound
    let progress: DuelProgress
    func validate(id: String) throws {
        try round.validate(); try progress.validate()
        guard round.id == id else { throw SocialError.invalid }
    }
}
struct DuelLeader: Decodable, Identifiable, Sendable {
    let id: String; let name: String; let handle: String; let avatarColor: String
    var avatarID: String? = nil
    var avatarPhotoID: String? = nil
    let rank: Int; let points: Int
}
struct DuelLeaderboard: Decodable, Sendable {
    let month: String; let leaders: [DuelLeader]; let me: DuelLeader?
    func validate(owner: String) throws {
        guard leaders.count <= 30, Set(leaders.map(\.id)).count == leaders.count,
              leaders.allSatisfy({ !$0.id.isEmpty && $0.rank > 0 && $0.points > 0 && $0.points <= 310 && $0.points % 10 == 0 }),
              me == nil || me?.id == owner else { throw SocialError.invalid }
    }
}
@MainActor protocol DailyDuelsAPI: Sendable {
    func dailyDuels() async throws -> DailyDuelHub
    func dailyDuel(id: String) async throws -> DailyDuelDetail
    func duelLeaderboard() async throws -> DuelLeaderboard
    func voteDailyDuel(id: String, choice: Int) async throws -> PostReceipt
}
extension AccountAPIClient: DailyDuelsAPI {
    func dailyDuels() async throws -> DailyDuelHub { try await request("community/daily-duels") }
    func dailyDuel(id: String) async throws -> DailyDuelDetail { try await request("community/daily-duels/" + id) }
    func duelLeaderboard() async throws -> DuelLeaderboard { try await request("community/daily-duels/leaderboard") }
    func voteDailyDuel(id: String, choice: Int) async throws -> PostReceipt { try await votePost(id, choice: choice) }
}

/// Invitations remain readable text for older clients. Only an exact app-owned URI becomes a route.
enum DuelInvitation {
    static func url(id: String) -> URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        return URL(string: "multiverse://duel/" + id.lowercased())
    }
    static func displayText(in text: String) -> String {
        guard id(in: text) != nil else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false).dropLast().joined(separator: "\n")
    }
    static func id(in text: String) -> String? {
        guard let last = text.split(separator: "\n").last, let url = URL(string: String(last)),
              url.scheme == "multiverse", url.host == "duel", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil, url.pathComponents.count == 2,
              let id = url.pathComponents.last, UUID(uuidString: id) != nil else { return nil }
        return id.lowercased()
    }
}
