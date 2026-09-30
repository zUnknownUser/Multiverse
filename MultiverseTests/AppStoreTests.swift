import Testing
@testable import Multiverse

struct AppStoreTests {

    /// `checks[id]` explícito manda mais que o diário — mesmo pra um item já registrado,
    /// desmarcar numa ordem tem que deixar de contar como visto (ver README, "Interações").
    @Test func isSeenPrioritizesExplicitCheckOverDiary() async throws {
        let store = AppStore(repository: MockRepository(startFollowing: true))
        await store.bootstrap()
        let itemID = try #require(store.diary.first).itemId

        #expect(store.isSeen(itemID))
        store.toggleSeen(itemID)
        #expect(store.isSeen(itemID) == false)
    }

    @Test func toggleFollowPersistsThroughRepository() async throws {
        let repository = MockRepository(startFollowing: false)
        let store = AppStore(repository: repository)
        await store.bootstrap()
        let someone = try #require(store.users.first { $0.id != store.meID }).id

        #expect(store.isFollowing(someone) == false)
        store.toggleFollow(someone, silent: true)
        #expect(store.isFollowing(someone))

        try await Task.sleep(for: .milliseconds(600))
        let persisted = await repository.fetchFollows()
        #expect(persisted.contains(someone))
    }

    @Test func voteWeeklyIsLockedAfterFirstChoice() async {
        let store = AppStore(repository: MockRepository(startFollowing: true))
        await store.bootstrap()

        store.voteWeekly(0)
        store.voteWeekly(1)

        #expect(store.pollVote == 0)
    }
}
