import Foundation
import Observation

/// Discovery and relationships have their own state; they never read demo users.
@MainActor @Observable
final class PeopleStore {
    private let api: any PeopleAPI
    private let ownerID: String
    private(set) var state: SocialState?
    private(set) var profiles: [String: PersonSummary] = [:]
    private var suggestionIDs: [String] = []
    private(set) var searchIDs: [String] = []
    private(set) var searchQuery = ""
    private(set) var nextCursor: String?
    private(set) var homeError: String?
    private(set) var searchError: String?
    private(set) var profileErrors: [String: String] = [:]
    private(set) var followError: String?
    private(set) var isLoadingHome = false
    private(set) var isSearching = false
    private(set) var savingPersonID: String?
    private(set) var discoveryEpoch = 0
    private var mutationRevision = 0
    private var searchGeneration = 0
    private var loadingProfiles = Set<String>()

    init(api: any PeopleAPI, ownerID: String) { self.api = api; self.ownerID = ownerID }
    var followingIDs: Set<String> { Set(state?.followingIDs ?? []) }
    var suggestions: [User] { suggestionIDs.filter { !followingIDs.contains($0) }.compactMap { profiles[$0]?.user } }
    var canFollow: Bool { state != nil && savingPersonID == nil }

    private func apply(_ incoming: SocialState, people: [PersonSummary], revision: Int) {
        guard incoming.version >= (state?.version ?? -1) else { return }
        state = incoming
        for person in people where revision == mutationRevision || profiles[person.id] == nil { profiles[person.id] = person }
    }

    func invalidateDiscovery() {
        discoveryEpoch += 1
        state = nil; profiles = [:]; suggestionIDs = []; isLoadingHome = false
        loadingProfiles = []; profileErrors = [:]; homeError = nil; followError = nil
        prepareSearch(searchQuery)
    }

    func loadHome() async {
        guard !isLoadingHome else { return }
        isLoadingHome = true; homeError = nil
        let epoch = discoveryEpoch
        let revision = mutationRevision
        defer { if epoch == discoveryEpoch { isLoadingHome = false } }
        do {
            let page = try await api.suggestedPeople()
            try Task.checkCancellation()
            guard epoch == discoveryEpoch else { return }
            try page.validate(ownerID: ownerID)
            apply(page.state, people: page.users, revision: revision)
            suggestionIDs = page.users.map(\.id)
        } catch is CancellationError { return }
        catch { if epoch == discoveryEpoch { homeError = error.localizedDescription } }
    }

    func prepareSearch(_ query: String) {
        searchGeneration += 1
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchIDs = []; nextCursor = nil; searchError = nil; isSearching = false
    }

    func search(more: Bool = false) async {
        guard !isSearching, !more || nextCursor != nil else { return }
        guard searchQuery.utf16.count <= 80 else { searchError = PeopleError.invalidSearch.localizedDescription; return }
        let generation = searchGeneration
        let epoch = discoveryEpoch
        let revision = mutationRevision
        let cursor = more ? nextCursor : nil
        isSearching = true; searchError = nil
        defer { if generation == searchGeneration { isSearching = false } }
        do {
            let page = try await api.searchPeople(query: searchQuery, after: cursor)
            try Task.checkCancellation()
            guard generation == searchGeneration else { return }
            guard epoch == discoveryEpoch else { return }
            try page.validate(ownerID: ownerID)
            guard page.nextCursor == nil || page.nextCursor != cursor else { throw AuthError.apiUnavailable }
            apply(page.state, people: page.users, revision: revision)
            let existing = more ? searchIDs : []
            searchIDs = existing + page.users.map(\.id).filter { !existing.contains($0) }
            nextCursor = page.nextCursor
        } catch is CancellationError { return }
        catch { if generation == searchGeneration { searchError = error.localizedDescription } }
    }

    func loadProfile(_ id: String) async {
        guard !loadingProfiles.contains(id) else { return }
        loadingProfiles.insert(id); profileErrors[id] = nil
        let epoch = discoveryEpoch
        let revision = mutationRevision
        defer { if epoch == discoveryEpoch { loadingProfiles.remove(id) } }
        do {
            let result = try await api.fetchPerson(id: id)
            try Task.checkCancellation()
            guard epoch == discoveryEpoch else { return }
            try result.validate(ownerID: ownerID, personID: id)
            apply(result.state, people: [result.person], revision: revision)
        } catch is CancellationError { return }
        catch { if epoch == discoveryEpoch { profileErrors[id] = error.localizedDescription } }
    }

    func setFollowing(_ id: String, following: Bool) async -> Bool {
        guard id != ownerID, canFollow else { return false }
        let epoch = discoveryEpoch
        savingPersonID = id; followError = nil; mutationRevision += 1
        defer { savingPersonID = nil }
        do {
            let result = try await api.setFollowing(id: id, following: following)
            guard epoch == discoveryEpoch else { return false }
            try result.validate(ownerID: ownerID, personID: id)
            guard result.state.followingIDs.contains(id) == following else { throw PeopleError.followFailed }
            apply(result.state, people: [result.person], revision: mutationRevision)
            return true
        } catch {
            if epoch == discoveryEpoch { followError = error.localizedDescription }
            return false
        }
    }
}
