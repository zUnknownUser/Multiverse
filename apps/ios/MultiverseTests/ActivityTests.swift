import Foundation
import Testing
@testable import Multiverse

@MainActor
private final class ActivityStub: ActivityAPI {
    var snapshot = ActivitySnapshot(entries: [], reviews: [], items: [], universes: [], followerCount: 0)
    var readFailure = false
    var requests: [(UUID, SaveLogInput)] = []
    var pending: CheckedContinuation<ActivitySnapshot, any Error>?
    func fetchActivity() async throws -> ActivitySnapshot {
        if readFailure { throw AuthError.networkUnavailable }
        return snapshot
    }
    func saveLog(id: UUID, input: SaveLogInput) async throws -> ActivitySnapshot {
        requests.append((id, input))
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func complete(_ result: Result<ActivitySnapshot, any Error>) {
        pending?.resume(with: result)
        pending = nil
    }
}

@MainActor
struct ActivityTests {
    private func saved(_ id: UUID = UUID()) -> ActivitySnapshot {
        let sample = SampleData.load()
        let item = sample.items.first { $0.id == "w-wotlk" }!
        return ActivitySnapshot(entries: [DiaryEntry(id: id, itemId: item.id, loggedAt: Date(timeIntervalSince1970: 1_790_000_000), rating: 4)],
            reviews: [ActivityReview(id: UUID().uuidString, user: "duda", item: item.id, rating: 4, text: "Minha review", spoiler: true, createdAt: .now)],
            items: [item], universes: sample.universes.filter { $0.id == item.uni }, followerCount: 2)
    }
    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
    @Test func emptyIsSuccessAndFailedReadCanRecoverWithoutFakeWidgets() async {
        let api = ActivityStub()
        api.readFailure = true
        let writer = WidgetSnapshotSpy()
        let store = AppStore(widgetWriter: writer, activityAPI: api)
        await store.bootstrap()
        #expect(store.activityLoadError != nil)
        #expect(writer.snapshots.isEmpty)
        api.readFailure = false
        await store.reloadAccount()
        #expect(store.activityLoadError == nil)
        #expect(store.diary.isEmpty)
        #expect(store.reviews.allSatisfy { $0.user != store.meID })
    }
    @Test func serverHistorySurvivesReopening() async {
        let api = ActivityStub()
        api.snapshot = saved()
        for _ in 0..<2 {
            let store = AppStore(activityAPI: api)
            await store.bootstrap()
            #expect(store.diary == api.snapshot.entries)
            #expect(store.reviews.filter { $0.user == store.meID }.map(\.text) == ["Minha review"])
            #expect(store.item("w-wotlk") != nil)
        }
    }
    @Test func failedSaveKeepsDraftAndRetryKeepsIdentityUntilConfirmed() async throws {
        let api = ActivityStub()
        let store = AppStore(activityAPI: api)
        await store.bootstrap()
        store.openLog(for: "w-wotlk")
        store.logDraft?.text = "Minha review"
        store.logDraft?.rating = 4
        let id = try #require(store.logDraft?.id)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        store.saveLog(at: date)
        store.saveLog(at: date)
        try await settle { api.pending != nil }
        #expect(api.requests.count == 1)
        #expect(store.isSavingLog)
        #expect(store.logDraft != nil)
        #expect(store.diary.isEmpty)
        api.complete(.failure(ActivityError.timedOut))
        try await settle { !store.isSavingLog }
        #expect(store.logSaveError != nil)
        #expect(store.logDraft?.text == "Minha review")
        #expect(store.logDraft?.id == id)
        store.saveLog(at: date.addingTimeInterval(60))
        try await settle { api.pending != nil }
        #expect(api.requests.count == 2)
        #expect(api.requests[0].0 == api.requests[1].0)
        #expect(api.requests[0].1 == api.requests[1].1)
        api.snapshot = saved(id)
        api.complete(.success(api.snapshot))
        try await settle { !store.isSavingLog }
        #expect(store.logDraft == nil)
        #expect(store.logSaveError == nil)
        #expect(store.diary.map(\.id) == [id])
    }
    @Test func missingAcknowledgementAndOversizedTextPreserveDraft() async throws {
        let api = ActivityStub()
        let store = AppStore(activityAPI: api)
        await store.bootstrap()
        store.openLog(for: "w-wotlk")
        store.logDraft?.text = String(repeating: "a", count: 5001)
        store.saveLog()
        #expect(api.requests.isEmpty)
        #expect(store.logSaveError == ActivityError.tooLong.localizedDescription)
        store.logDraft?.text = "Still here"
        store.saveLog()
        try await settle { api.pending != nil }
        api.complete(.success(api.snapshot))
        try await settle { !store.isSavingLog }
        #expect(store.logDraft?.text == "Still here")
        #expect(store.logSaveError != nil)
        #expect(store.diary.isEmpty)
    }
    @Test func reviewFromAnotherAccountIsRejected() {
        #expect(throws: AuthError.apiUnavailable) { try saved().validate(for: "other-user") }
    }
}
