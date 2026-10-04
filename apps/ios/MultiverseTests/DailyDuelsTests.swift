import Foundation
import Testing
@testable import Multiverse

@MainActor private final class DuelStub: DailyDuelsAPI {
    let id = UUID().uuidString.lowercased()
    var choice: Int?
    var saved = true
    var failure = false
    var reads = 0
    var counts: [Int] = [0,0]
    var calls: [Int] = []
    var hubHook: (() async throws -> DailyDuelHub)?
    var round: DailyDuelRound { .init(id: id, day: "2026-10-03", opensAt: .now.addingTimeInterval(-1000), closesAt: .now.addingTimeInterval(5000), universeID: "marvel", title: "A ou B?", text: "Editorial", optionA: "A", optionB: "B", votes: .init(counts: counts, mine: choice), commentCount: 0) }
    var progress: DuelProgress { .init(rounds: choice == nil ? 0 : 1, monthlyPoints: choice == nil ? 0 : 10, streak: choice == nil ? 0 : 1) }
    func dailyDuels() async throws -> DailyDuelHub { reads += 1; if let hubHook { return try await hubHook() }; if failure { throw AuthError.networkUnavailable }; return .init(serverTime: .now, today: round, previous: nil, progress: progress) }
    func dailyDuel(id: String) async throws -> DailyDuelDetail { if failure { throw AuthError.networkUnavailable }; return .init(serverTime: .now, round: round, progress: progress) }
    func duelLeaderboard() async throws -> DuelLeaderboard { .init(month: "2026-10", leaders: [], me: nil) }
    func voteDailyDuel(id: String, choice: Int) async throws -> PostReceipt {
        calls.append(choice)
        if saved { self.choice = choice; counts = choice == 0 ? [1,0] : [0,1] }
        return .init(id: id, saved: saved)
    }
}
@Suite(.serialized) @MainActor struct DailyDuelsTests {
    @Test func dailyDuelsCanBeInjectedWithoutAnAccountClient() async {
        let api = DuelStub()
        let store = AppStore(dailyDuelsAPI: api)
        await store.dailyDuels?.refresh()
        #expect(store.dailyDuels?.hub?.today?.id == api.id)
        #expect(!store.usesAccountAPI)
    }
    @Test func homeCachesSuccessfulReadsAndKeepsLastKnownDataOffline() async {
        let api = DuelStub(), store = DailyDuelsStore(api: api)
        await store.refresh(); await store.refresh()
        #expect(api.reads == 1 && store.hub?.today?.id == api.id)
        api.failure = true; await store.refresh(force: true)
        #expect(store.hub?.today?.id == api.id && store.error != nil)
        api.failure = false; await store.refresh(force: true)
        #expect(store.error == nil)
    }
    @Test func confirmedVotesUpdateHomeAndChangingSidesDoesNotInventPoints() async throws {
        let api = DuelStub(), store = DailyDuelsStore(api: api)
        await store.refresh()
        _ = try await store.vote(id: api.id, choice: 0)
        #expect(store.hub?.today?.votes.mine == 0 && store.hub?.progress.monthlyPoints == 10)
        _ = try await store.vote(id: api.id, choice: 1)
        #expect(store.hub?.today?.votes.counts == [0,1] && store.hub?.progress.monthlyPoints == 10)
    }
    @Test func failedReceiptNeverInventsVoteOrRewardAndMalformedRoundIsRejected() async {
        let api = DuelStub(), store = DailyDuelsStore(api: api)
        await store.refresh(); api.saved = false
        await #expect(throws: (any Error).self) { try await store.vote(id: api.id, choice: 0) }
        #expect(store.hub?.today?.votes.mine == nil && store.hub?.progress.monthlyPoints == 0 && !store.voting)
        api.counts = [1]
        await store.refresh(force: true)
        #expect(store.error != nil && store.hub?.today?.votes.counts == [0,0])
    }
    @Test func resultReadFailureCanRetryAnAlreadySavedVote() async throws {
        let api = DuelStub(), store = DailyDuelsStore(api: api)
        await store.refresh(); api.failure = true
        await #expect(throws: (any Error).self) { try await store.vote(id: api.id, choice: 0) }
        #expect(store.hub?.progress.rounds == 0)
        api.failure = false
        let retried = try await store.vote(id: api.id, choice: 0)
        #expect(retried.progress.rounds == 1 && retried.progress.monthlyPoints == 10)
    }
    @Test func invitationRoutesAcceptOnlyAnExactAppURI() {
        let id = UUID().uuidString.lowercased()
        #expect(DuelInvitation.id(in: "Invitation\nmultiverse://duel/" + id) == id)
        for value in ["https://duel/"+id, "multiverse://duel/"+id+"?admin=true", "multiverse://x@duel/"+id, "multiverse://duel/not-a-uuid", "multiverse://duel/"+id+"/other"] { #expect(DuelInvitation.id(in: value) == nil) }
    }
    @Test func delayedHomeRefreshCannotOverwriteAConfirmedVote() async throws {
        let api = DuelStub(), store = DailyDuelsStore(api: api)
        await store.refresh()
        let stale = try #require(store.hub)
        var continuation: CheckedContinuation<DailyDuelHub, any Error>?
        api.hubHook = { try await withCheckedThrowingContinuation { continuation = $0 } }
        let refresh = Task { await store.refresh(force: true) }
        while continuation == nil { await Task.yield() }
        _ = try await store.vote(id: api.id, choice: 1)
        continuation?.resume(returning: stale)
        await refresh.value
        #expect(store.hub?.today?.votes.mine == 1 && store.hub?.progress.monthlyPoints == 10)
    }
    @Test func milestonesAreLifetimeParticipationAndDoNotDependOnWinning() {
        #expect(DuelProgress(rounds: 0, monthlyPoints: 0, streak: 0).nextMilestone == 1)
        #expect(DuelProgress(rounds: 7, monthlyPoints: 0, streak: 0).nextMilestone == 30)
        #expect(DuelProgress(rounds: 100, monthlyPoints: 0, streak: 0).nextMilestone == nil)
    }
}
