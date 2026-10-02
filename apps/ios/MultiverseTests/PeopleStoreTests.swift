import Foundation
import Testing
@testable import Multiverse

@MainActor
private final class PeopleStub: PeopleAPI {
    var state = SocialState(version: 0, followingIDs: [], followerCount: 2)
    var people = [PersonSummary(userID: "alice", username: "alice", displayName: "Alice", avatarColor: "#F4A814", bio: "Marvel", logCount: 7, followerCount: 0, followingCount: 1)]
    var failure = false
    var holdHome = false
    var holdSearch = false
    var holdWrite = false
    var homeContinuation: CheckedContinuation<PeoplePage, any Error>?
    var searches: [String: CheckedContinuation<PeoplePage, any Error>] = [:]
    var writeContinuation: CheckedContinuation<PersonEnvelope, any Error>?
    var writes: [(String, Bool)] = []
    var cursor: String?
    func page() -> PeoplePage { PeoplePage(users: people, nextCursor: cursor, state: state) }
    func suggestedPeople() async throws -> PeoplePage {
        if failure { throw AuthError.networkUnavailable }
        if holdHome { return try await withCheckedThrowingContinuation { homeContinuation = $0 } }
        return page()
    }
    func searchPeople(query: String, after: String?) async throws -> PeoplePage {
        if failure { throw AuthError.networkUnavailable }
        if holdSearch { return try await withCheckedThrowingContinuation { searches[query] = $0 } }
        return page()
    }
    func fetchPerson(id: String) async throws -> PersonEnvelope {
        guard !failure, let person = people.first(where: { $0.id == id }) else { throw PeopleError.unavailable }
        return PersonEnvelope(person: person, state: state)
    }
    func setFollowing(id: String, following: Bool) async throws -> PersonEnvelope {
        writes.append((id, following))
        if failure { throw AuthError.networkUnavailable }
        if holdWrite { return try await withCheckedThrowingContinuation { writeContinuation = $0 } }
        state = SocialState(version: state.version + 1, followingIDs: following ? [id] : [], followerCount: 2)
        let old = people[0]
        people[0] = PersonSummary(userID: old.id, username: old.username, displayName: old.displayName, avatarColor: old.avatarColor, bio: old.bio, logCount: old.logCount, followerCount: following ? 1 : 0, followingCount: old.followingCount)
        return PersonEnvelope(person: people[0], state: state)
    }
}

@MainActor
struct PeopleStoreTests {
    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }

    @Test func emptySuccessIsDifferentFromNetworkErrorAndRetryKeepsKnownPeople() async {
        let api = PeopleStub()
        let store = PeopleStore(api: api, ownerID: "owner")
        await store.loadHome()
        #expect(store.suggestions.map(\.id) == ["alice"])
        api.failure = true
        await store.loadHome()
        #expect(store.homeError != nil)
        #expect(store.suggestions.map(\.id) == ["alice"])
        api.failure = false; api.people = []
        await store.loadHome()
        #expect(store.homeError == nil)
        #expect(store.suggestions.isEmpty)
        #expect(store.state != nil)
    }

    @Test func confirmedFollowsSurviveReopeningAndUnfollowUpdatesActualCounts() async {
        let api = PeopleStub()
        let store = PeopleStore(api: api, ownerID: "owner")
        await store.loadHome()
        #expect(await store.setFollowing("alice", following: true))
        #expect(store.followingIDs == ["alice"])
        #expect(store.profiles["alice"]?.followerCount == 1)
        #expect(store.suggestions.isEmpty)
        let reopened = PeopleStore(api: api, ownerID: "owner")
        await reopened.loadHome()
        #expect(reopened.followingIDs == ["alice"])
        #expect(await reopened.setFollowing("alice", following: false))
        #expect(reopened.followingIDs.isEmpty)
        #expect(reopened.profiles["alice"]?.followerCount == 0)
        let another = PeopleStore(api: PeopleStub(), ownerID: "another")
        #expect(another.state == nil)
        #expect(another.profiles.isEmpty)
    }

    @Test func failedFollowPreservesPriorStateAndRetrySendsSameDesiredState() async {
        let api = PeopleStub()
        let store = PeopleStore(api: api, ownerID: "owner")
        await store.loadHome()
        api.failure = true
        #expect(!(await store.setFollowing("alice", following: true)))
        #expect(store.followError != nil)
        #expect(store.followingIDs.isEmpty)
        #expect(store.profiles["alice"]?.followerCount == 0)
        api.failure = false
        #expect(await store.setFollowing("alice", following: true))
        #expect(api.writes.map(\.1) == [true, true])
        #expect(store.followError == nil)
    }

    @Test func duplicateTapIsCoalescedAndMissingAcknowledgementIsNotSuccess() async throws {
        let api = PeopleStub()
        let store = PeopleStore(api: api, ownerID: "owner")
        await store.loadHome()
        api.holdWrite = true
        let task = Task { await store.setFollowing("alice", following: true) }
        try await settle { api.writeContinuation != nil }
        #expect(!store.canFollow)
        #expect(!(await store.setFollowing("alice", following: true)))
        #expect(api.writes.count == 1)
        api.writeContinuation?.resume(returning: PersonEnvelope(person: api.people[0], state: api.state))
        #expect(!(await task.value))
        #expect(store.followError != nil)
        #expect(store.followingIDs.isEmpty)
    }

    @Test func lateReadCannotUndoAcknowledgedFollowOrItsCount() async throws {
        let api = PeopleStub()
        let store = PeopleStore(api: api, ownerID: "owner")
        await store.loadHome()
        let oldPage = api.page()
        api.holdHome = true
        let read = Task { await store.loadHome() }
        try await settle { api.homeContinuation != nil }
        #expect(await store.setFollowing("alice", following: true))
        api.homeContinuation?.resume(returning: oldPage)
        await read.value
        #expect(store.followingIDs == ["alice"])
        #expect(store.profiles["alice"]?.followerCount == 1)
        #expect(store.suggestions.isEmpty)
    }

    @Test func obsoleteSearchCannotReplaceNewerResultsAndPaginationRejectsNonAdvancingCursor() async throws {
        let api = PeopleStub()
        let store = PeopleStore(api: api, ownerID: "owner")
        api.holdSearch = true
        store.prepareSearch("old")
        let old = Task { await store.search() }
        try await settle { api.searches["old"] != nil }
        store.prepareSearch("alice")
        let current = Task { await store.search() }
        try await settle { api.searches["alice"] != nil }
        api.searches["alice"]?.resume(returning: api.page())
        await current.value
        api.searches["old"]?.resume(returning: PeoplePage(users: [], nextCursor: nil, state: api.state))
        await old.value
        #expect(store.searchIDs == ["alice"])
        api.holdSearch = false; api.cursor = "alice"
        await store.search()
        await store.search(more: true)
        #expect(store.searchError != nil)
        #expect(store.searchIDs == ["alice"])
        store.prepareSearch(String(repeating: "a", count: 81))
        await store.search()
        #expect(store.searchError == PeopleError.invalidSearch.localizedDescription)
    }

    @Test func unavailableProfileAndInvalidOwnerDataNeverCreateFakeProfiles() async {
        let api = PeopleStub()
        let store = PeopleStore(api: api, ownerID: "owner")
        await store.loadProfile("missing")
        #expect(store.profileErrors["missing"] != nil)
        #expect(store.profiles["missing"] == nil)
        api.state = SocialState(version: 0, followingIDs: ["owner"], followerCount: 0)
        await store.loadHome()
        #expect(store.homeError != nil)
        #expect(store.state == nil)
    }

    @Test func appUsesRealProfileWithoutInventedAffinityOrHistory() async {
        let api = PeopleStub()
        let app = AppStore(peopleAPI: api)
        await app.bootstrap()
        await app.people?.loadHome()
        #expect(app.homeSuggestedPeople.map(\.id) == ["alice"])
        let profile = app.profileData(for: "alice")
        #expect(profile.stats.map(\.count) == ["7", "0", "1"])
        #expect(profile.compatPercent == nil)
        #expect(profile.recentReviews.isEmpty)
        #expect(profile.badges.isEmpty)
        app.people?.prepareSearch("alice")
        await app.people?.search()
        let rows = app.searchResults(query: "alice", filter: .people).rows
        #expect(rows.map(\.title) == ["Alice"])
    }
}
