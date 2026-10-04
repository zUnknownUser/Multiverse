import Testing
@testable import Multiverse

@MainActor private final class RoomsOnlyAPI: RoomsAPI {
    var visits = 0
    func fetchRooms(query: String, universe: String?, after: String?) async throws -> LiveRoomsPage {
        .init(rooms: [], nextCursor: nil)
    }
    func visitRoom(_ item: String, progress: Int?) async throws -> RoomVisit {
        visits += 1
        return .init(itemID: item, online: 1, progress: progress ?? 0)
    }
    func roomChanges(_ item: String, after: String?) async throws -> RoomChanges {
        throw CommunityError.unavailable
    }
}
@MainActor struct FeatureDependencyTests {
    @Test func roomsWorkWithoutImplementingClubsCommunityOrAccounts() async throws {
        let api = RoomsOnlyAPI()
        let store = AppStore(roomsAPI: api)
        #expect(store.clubsAPI == nil && store.communityAPI == nil && store.voiceAPI == nil)
        let result = try await store.roomsAPI?.visitRoom("m-civil", progress: 30)
        #expect(result?.progress == 30 && api.visits == 1)
    }
}
