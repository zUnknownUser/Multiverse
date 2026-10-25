import Foundation
import Testing
@testable import Multiverse

@MainActor
private final class ActivityStub: ActivityAPI {
    var snapshot = ActivitySnapshot(entries: [], reviews: [], items: [], universes: [], followerCount: 0)
    var readFailure = false
    var requests: [(UUID, SaveLogInput)] = []
    var pending: CheckedContinuation<ActivitySnapshot, any Error>?
    var holdReads = false
    var pendingRead: CheckedContinuation<ActivitySnapshot, any Error>?
    var readCount = 0
    func fetchActivity() async throws -> ActivitySnapshot {
        readCount += 1
        if readFailure { throw AuthError.networkUnavailable }
        if holdReads { return try await withCheckedThrowingContinuation { pendingRead = $0 } }
        return snapshot
    }
    func saveLog(id: UUID, input: SaveLogInput) async throws -> ActivitySnapshot {
        requests.append((id, input))
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    var updateIDs: [UUID] = []
    var deleteIDs: [UUID] = []
    var pendingDelete: CheckedContinuation<DeleteLogReceipt, any Error>?
    func updateLog(id: UUID, input: SaveLogInput) async throws -> ActivitySnapshot {
        updateIDs.append(id)
        return try await saveLog(id: id, input: input)
    }
    func deleteLog(id: UUID) async throws -> DeleteLogReceipt {
        deleteIDs.append(id)
        return try await withCheckedThrowingContinuation { pendingDelete = $0 }
    }
    func completeDelete(_ result: Result<DeleteLogReceipt, any Error>) {
        pendingDelete?.resume(with: result)
        pendingDelete = nil
    }
    func complete(_ result: Result<ActivitySnapshot, any Error>) {
        pending?.resume(with: result)
        pending = nil
    }
    func completeRead(_ snapshot: ActivitySnapshot) {
        pendingRead?.resume(returning: snapshot)
        pendingRead = nil
    }
}

@MainActor
struct ActivityTests {
    private func acknowledged(_ api: ActivityStub) throws -> ActivitySnapshot {
        let (id, input) = try #require(api.requests.last)
        let sample = SampleData.load()
        let item = try #require(sample.items.first { $0.id == input.itemId })
        return ActivitySnapshot(entries: [DiaryEntry(id: id, itemId: input.itemId, loggedAt: input.loggedAt,
            rating: input.rating, liked: input.liked, rewatch: input.rewatch)],
            reviews: input.rating == 0 && input.text.isEmpty ? [] : [ActivityReview(id: UUID().uuidString, user: "duda", item: input.itemId, rating: input.rating,
                text: input.text, spoiler: input.spoiler, createdAt: .now, entryId: id)],
            items: [item], universes: sample.universes.filter { $0.id == item.uni }, followerCount: 2)
    }
    private func saved(_ id: UUID = UUID()) -> ActivitySnapshot {
        let sample = SampleData.load()
        let item = sample.items.first { $0.id == "m-civil" }!
        return ActivitySnapshot(entries: [DiaryEntry(id: id, itemId: item.id, loggedAt: Date(timeIntervalSince1970: 1_790_000_000), rating: 4)],
            reviews: [ActivityReview(id: UUID().uuidString, user: "duda", item: item.id, rating: 4, text: "Minha review", spoiler: true, createdAt: .now, entryId: id)],
            items: [item], universes: sample.universes.filter { $0.id == item.uni }, followerCount: 2)
    }
    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
    @Test func interruptedSaveCanResumeAfterRestartWithSameIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FileLogDraftStorage(userID: "duda", environment: .staging, directory: directory)
        let api = ActivityStub()
        let first = AppStore(activityAPI: api, draftStorage: storage)
        await first.bootstrap()
        first.openLog(for: "m-civil")
        first.logDraft?.text = "Persistir também quando a resposta se perde"
        first.saveLog()
        try await settle { api.pending != nil }
        let initial = try #require(api.requests.first)
        api.complete(.failure(AuthError.networkUnavailable))
        try await settle { !first.isSavingLog }
        first.closeLog()
        let next = AppStore(activityAPI: api, draftStorage: storage)
        await next.bootstrap()
        next.openLogBlank()
        next.saveLog()
        try await settle { api.pending != nil }
        #expect(api.requests.last?.0 == initial.0)
        #expect(api.requests.last?.1 == initial.1)
        api.complete(.success(try acknowledged(api)))
        try await settle { !next.isSavingLog }
        #expect(next.logDraft == nil)
        #expect(next.savedLogDraft == nil)
        #expect(try storage.load() == nil)
        #expect(next.diary.count == 1)
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
        await store.refreshActivity()
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
            #expect(store.item("m-civil") != nil)
        }
    }
    @Test func failedSaveKeepsDraftAndRetryKeepsIdentityUntilConfirmed() async throws {
        let api = ActivityStub()
        let store = AppStore(activityAPI: api)
        await store.bootstrap()
        store.openLog(for: "m-civil")
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
        api.snapshot = try acknowledged(api)
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
        store.openLog(for: "m-civil")
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

    @Test func realActivityDoesNotInheritDemoReviewsOrFavorites() async {
        let api = ActivityStub()
        let store = AppStore(activityAPI: api)
        await store.bootstrap()
        #expect(store.reviews.isEmpty)
        #expect(store.profileData(for: store.meID).favorites.isEmpty)
        #expect(store.profileData(for: store.meID).stats.first?.count == "0")
        #expect(store.profileData(for: store.meID).recentReviews.isEmpty)
        #expect(store.homeEmptyFeedMessage == L10n.text("Seu espaço começa com uma obra. Explore o catálogo e faça seu primeiro registro."))
        let history = saved()
        api.snapshot = ActivitySnapshot(entries: history.entries, reviews: [], items: history.items, universes: history.universes, followerCount: 0)
        await store.refreshActivity()
        #expect(store.homeFeed().isEmpty)
        #expect(store.homeEmptyFeedMessage == L10n.text("Seus registros estão no diário. Adicione uma nota ou review para aparecer aqui."))
    }

    @Test func favoritesAndProfileReflectConfirmedLogsAndSurviveReopening() async throws {
        let api = ActivityStub()
        let store = AppStore(activityAPI: api)
        await store.bootstrap()
        store.openLog(for: "m-civil")
        store.logDraft?.liked = true
        store.logDraft?.rating = 4.5
        store.logDraft?.text = "Meu texto permanece em português."
        store.saveLog()
        try await settle { api.pending != nil }
        api.snapshot = try acknowledged(api)
        api.complete(.success(api.snapshot))
        try await settle { !store.isSavingLog }
        for current in [store, AppStore(activityAPI: api)] {
            await current.bootstrap()
            let profile = current.profileData(for: current.meID)
            #expect(profile.stats.first?.count == "1")
            #expect(profile.favorites.map(\.id) == ["m-civil"])
            #expect(profile.recentReviews.map(\.text) == ["Meu texto permanece em português."])
            #expect(current.reviewsForItem("m-civil", friendsOnly: false).count == 1)
            #expect(current.myDiaryEntry(for: "m-civil")?.rating == 4.5)
        }
        // A newer unliked revisit removes the favorite; the old log remains in history.
        let prior = api.snapshot
        api.snapshot = ActivitySnapshot(entries: [DiaryEntry(itemId: "m-civil", loggedAt: .now,
            rating: 3, liked: false, rewatch: true)] + prior.entries, reviews: prior.reviews,
            items: prior.items, universes: prior.universes, followerCount: prior.followerCount)
        await store.refreshActivity()
        #expect(store.diary.count == 2)
        #expect(store.profileData(for: store.meID).favorites.isEmpty)
    }

    @Test func refreshFailureKeepsHistoryAndCanRecoverInPlace() async {
        let api = ActivityStub()
        api.snapshot = saved()
        let store = AppStore(activityAPI: api)
        await store.bootstrap()
        api.readFailure = true
        await store.refreshActivity()
        #expect(store.activityRefreshError != nil)
        #expect(store.activityLoadError == nil)
        #expect(store.diary == api.snapshot.entries)
        #expect(!store.isLoading && !store.isRefreshingActivity)
        api.readFailure = false
        await store.refreshActivity()
        #expect(store.activityRefreshError == nil)
    }

    @Test func delayedRefreshCannotUndoANewSaveOrCreateParallelReads() async throws {
        let api = ActivityStub()
        let store = AppStore(activityAPI: api)
        await store.bootstrap()
        let old = api.snapshot
        api.holdReads = true
        let refresh = Task { await store.refreshActivity() }
        try await settle { api.pendingRead != nil }
        await store.refreshActivity()
        #expect(api.readCount == 2) // bootstrap + one refresh
        store.openLog(for: "m-civil")
        store.logDraft?.rating = 5
        store.saveLog()
        try await settle { api.pending != nil }
        api.snapshot = try acknowledged(api)
        api.complete(.success(api.snapshot))
        try await settle { !store.isSavingLog }
        api.completeRead(old)
        await refresh.value
        #expect(store.diary == api.snapshot.entries)
        #expect(store.diary.count == 1)
    }

    @Test func mismatchedAcknowledgementKeepsDraftAndRatingCanBeCleared() async throws {
        let api = ActivityStub()
        let store = AppStore(activityAPI: api)
        await store.bootstrap()
        store.openLog(for: "m-civil")
        store.setLogRating(5)
        #expect(store.logDraft?.rating == 5)
        store.setLogRating(5)
        #expect(store.logDraft?.rating == 4.5)
        store.setLogRating(5)
        #expect(store.logDraft?.rating == 0)
        let id = try #require(store.logDraft?.id)
        store.saveLog()
        try await settle { api.pending != nil }
        api.complete(.success(saved(id))) // Same UUID, wrong work: not a confirmation.
        try await settle { !store.isSavingLog }
        #expect(store.logDraft?.id == id)
        #expect(store.logSaveError != nil)
        #expect(store.diary.isEmpty)
    }

    @Test func anotherSessionStartsWithItsOwnEmptyActivity() async {
        let api = ActivityStub()
        api.snapshot = saved()
        let first = AppStore(activityAPI: api)
        await first.bootstrap()
        first.openLog(for: "m-civil")
        first.logDraft?.text = "Rascunho privado"
        let second = AppStore(session: AuthSession(userID: "other", email: "other@example.test", handle: "@other"), activityAPI: ActivityStub())
        await second.bootstrap()
        #expect(second.meID == "other")
        #expect(second.diary.isEmpty && second.reviews.isEmpty)
        #expect(second.logDraft == nil)
        #expect(second.profileData(for: "other").favorites.isEmpty)
        #expect(first.diary.count == 1)
    }

    @Test func communityHistogramNeverFallsBackToSampleVotesForAPIItems() throws {
        var item = try #require(SampleData.load().items.first)
        item.logCount = 0
        #expect(Logic.ratingHistogram(item) == Array(repeating: 0, count: 10))
        item.ratingHistogram = [0, 0, 0, 0, 0, 0, 0, 2, 1, 0]
        #expect(Logic.ratingHistogram(item) == item.ratingHistogram)
        item.ratingHistogram = [-1]
        #expect(Logic.ratingHistogram(item) == Array(repeating: 0, count: 10))
    }

    @Test func rejectedFutureDateCanBeCorrectedWithoutDiscardingReview() async throws {
        let api = ActivityStub()
        let store = AppStore(activityAPI: api)
        await store.bootstrap()
        store.openLog(for: "m-civil")
        store.logDraft?.text = "Preserve this review"
        store.saveLog(at: .now.addingTimeInterval(86400))
        try await settle { api.pending != nil }
        api.complete(.failure(ActivityError.invalidDate))
        try await settle { !store.isSavingLog }
        #expect(store.logDraft?.loggedAt == nil)
        let corrected = Date.now
        store.saveLog(at: corrected)
        try await settle { api.pending != nil }
        #expect(api.requests[0].0 == api.requests[1].0)
        #expect(api.requests[1].1.loggedAt == corrected)
        #expect(api.requests[1].1.text == "Preserve this review")
        api.complete(.success(try acknowledged(api)))
        try await settle { !store.isSavingLog }
        #expect(store.logDraft == nil)
    }

    @Test func editingTargetsTheExactRevisitAndRetriesWithoutCreatingAnotherEntry() async throws {
        let api = ActivityStub(), first = UUID(), second = UUID()
        let original = saved(first)
        let revisit = DiaryEntry(id: second, itemId: "m-civil", loggedAt: .now, rating: 2, liked: true, rewatch: true)
        let review = ActivityReview(id: UUID().uuidString, user: "duda", item: "m-civil", rating: 2,
                                   text: "Second visit", spoiler: false, createdAt: .now, entryId: second)
        api.snapshot = .init(entries: [revisit] + original.entries, reviews: [review] + original.reviews,
                             items: original.items, universes: original.universes, followerCount: 2)
        let store = AppStore(activityAPI: api)
        await store.bootstrap()
        store.editLog(id: first)
        #expect(store.logDraft?.text == "Minha review" && store.logDraft?.spoiler == true)
        store.closeLog()
        #expect(api.requests.isEmpty) // Cancelling does not save.
        store.editLog(id: second)
        #expect(store.logDraft?.id == second && store.logDraft?.isEditing == true)
        #expect(store.logDraft?.text == "Second visit" && store.logDraft?.liked == true)
        #expect(store.logDraft?.rewatch == true && store.logDraft?.loggedAt == revisit.loggedAt)
        store.setLogItem("m-ultimato")
        #expect(store.logDraft?.itemID == "m-civil")
        store.logDraft?.text = "Edited revisit"
        store.logDraft?.rating = 3.5
        store.logDraft?.loggedAt = original.entries[0].loggedAt
        store.saveLog()
        store.saveLog()
        try await settle { api.pending != nil }
        #expect(api.updateIDs == [second])
        api.complete(.failure(ActivityError.timedOut))
        try await settle { !store.isSavingLog }
        #expect(store.diary.count == 2 && store.logDraft?.text == "Edited revisit")
        store.saveLog()
        try await settle { api.pending != nil }
        #expect(api.updateIDs == [second, second] && api.requests[0].1 == api.requests[1].1)
        let updated = try acknowledged(api)
        api.snapshot = .init(entries: updated.entries + original.entries, reviews: updated.reviews + original.reviews,
                             items: original.items, universes: original.universes, followerCount: 2)
        api.complete(.success(api.snapshot))
        try await settle { !store.isSavingLog }
        #expect(store.logDraft == nil && store.diary.count == 2)
        store.editLog(id: second)
        #expect(store.logDraft?.text == "Edited revisit" && store.logDraft?.rating == 3.5)
        store.closeLog()
        store.openLog(for: "m-civil")
        #expect(store.logDraft?.id != second && store.logDraft?.isEditing == false)
    }

    @Test func editingKeepsTheDraftWhenReviewConfirmationIsWrongOrTheEntryWasDeleted() async throws {
        let api = ActivityStub()
        api.snapshot = saved()
        let id = api.snapshot.entries[0].id, store = AppStore(activityAPI: api)
        await store.bootstrap()
        store.editLog(id: id)
        store.logDraft?.text = "New text"
        store.saveLog()
        try await settle { api.pending != nil }
        api.complete(.success(api.snapshot)) // The entry matches but the review does not.
        try await settle { !store.isSavingLog }
        #expect(store.logSaveError != nil && store.logDraft?.text == "New text")
        store.saveLog()
        try await settle { api.pending != nil }
        api.complete(.failure(ActivityError.deletedLog))
        try await settle { !store.isSavingLog }
        #expect(store.logDraft?.id == id && store.logDraft?.isEditing == true)
        #expect(store.logSaveError == ActivityError.deletedLog.localizedDescription)
    }

    @Test func editingRatingOnlyEntryRestoresEmptyTextAndCanRemoveItsReview() async throws {
        let api = ActivityStub(), id = UUID()
        let initial = saved(id)
        api.snapshot = .init(entries: initial.entries,
                             reviews: [.init(id: UUID().uuidString, user: "duda", item: "m-civil", rating: 4, text: "", spoiler: false, createdAt: .now, entryId: id)],
                             items: initial.items, universes: initial.universes, followerCount: 0)
        let store = AppStore(activityAPI: api)
        await store.bootstrap()
        store.editLog(id: id)
        #expect(store.logDraft?.text == "") // Never save the display-only “Rated this work.” text.
        store.logDraft?.rating = 0
        store.saveLog()
        try await settle { api.pending != nil }
        api.complete(.success(try acknowledged(api)))
        try await settle { !store.isSavingLog }
        #expect(store.diary.count == 1 && store.diary[0].rating == 0 && store.reviews.isEmpty)
    }

    private func deletedState(_ initial: ActivitySnapshot) -> ActivitySnapshot {
        let item = initial.items[0]
        let updated = Item(id: item.id, uni: item.uni, type: item.type, title: item.title, year: item.year,
                           avg: 0, canon: item.canon, desc: item.desc, logCount: 0, reviewCount: 0, ratingHistogram: Array(repeating: 0, count: 10))
        return .init(entries: [], reviews: [], items: [updated], universes: initial.universes, followerCount: 2)
    }

    @Test(arguments: [false, true]) func deletionReconcilesActivityWithoutErasingManualSeenState(manuallySeen: Bool) async throws {
        let api = ActivityStub()
        api.snapshot = saved()
        let initial = api.snapshot, entry = initial.entries[0], store = AppStore(activityAPI: api)
        await store.bootstrap()
        store.checks[entry.itemId] = manuallySeen
        #expect(store.isSeen(entry.itemId))
        store.deleteLog(id: entry.id)
        store.deleteLog(id: entry.id)
        store.openLogBlank()
        try await settle { api.pendingDelete != nil }
        #expect(api.deleteIDs == [entry.id] && store.logDraft == nil && store.diary.count == 1)
        api.completeDelete(.failure(AuthError.networkUnavailable))
        try await settle { !store.isDeletingLog }
        #expect(store.diaryDeleteError != nil && store.diary == initial.entries)
        store.editLog(id: entry.id)
        #expect(store.logDraft == nil)
        store.deleteLog(id: entry.id)
        try await settle { api.pendingDelete != nil }
        api.snapshot = deletedState(initial)
        api.completeDelete(.success(.init(id: entry.id, state: api.snapshot)))
        try await settle { !store.isDeletingLog }
        #expect(api.deleteIDs == [entry.id, entry.id])
        #expect(store.diary.isEmpty && store.reviews.isEmpty && store.pendingDiaryDeletion == nil && store.diaryDeleteError == nil)
        #expect(store.item(entry.itemId)?.avg == 0 && store.item(entry.itemId)?.logCount == 0)
        #expect(store.isSeen(entry.itemId) == manuallySeen)
        #expect(store.profileData(for: store.meID).stats.first?.count == "0")
        #expect(store.profileData(for: store.meID).favorites.isEmpty)
        let reopened = AppStore(activityAPI: api)
        await reopened.bootstrap()
        #expect(reopened.diary.isEmpty && reopened.reviews.isEmpty)
    }

    @Test func delayedRefreshCannotRestoreADeletedEntry() async throws {
        let api = ActivityStub()
        api.snapshot = saved()
        let original = api.snapshot, store = AppStore(activityAPI: api)
        await store.bootstrap()
        api.holdReads = true
        let refresh = Task { await store.refreshActivity() }
        try await settle { api.pendingRead != nil }
        store.deleteLog(id: original.entries[0].id)
        try await settle { api.pendingDelete != nil }
        api.completeDelete(.success(.init(id: original.entries[0].id, state: deletedState(original))))
        try await settle { !store.isDeletingLog }
        api.completeRead(original)
        await refresh.value
        #expect(store.diary.isEmpty && store.reviews.isEmpty)
    }

    @Test func refreshingAfterLostDeleteResponseRetriesTheConfirmedActionAndUpdatesStatistics() async throws {
        let api = ActivityStub()
        api.snapshot = saved()
        let original = api.snapshot, entry = original.entries[0], store = AppStore(activityAPI: api)
        await store.bootstrap()
        store.deleteLog(id: entry.id)
        try await settle { api.pendingDelete != nil }
        api.completeDelete(.failure(ActivityError.timedOut))
        try await settle { !store.isDeletingLog }
        // A normal activity read would contain no items once the last log is gone.
        api.snapshot = .init(entries: [], reviews: [], items: [], universes: [], followerCount: 2)
        await store.refreshActivity()
        try await settle { api.pendingDelete != nil }
        #expect(api.readCount == 1 && api.deleteIDs == [entry.id, entry.id])
        api.completeDelete(.success(.init(id: entry.id, state: deletedState(original))))
        try await settle { !store.isDeletingLog }
        #expect(store.diary.isEmpty && store.pendingDiaryDeletion == nil)
        #expect(store.item(entry.itemId)?.logCount == 0 && store.item(entry.itemId)?.avg == 0)
    }

    @Test(arguments: ["wrong-id", "still-present", "missing-statistics"])
    func invalidDeletionReceiptKeepsHistoryAndRetry(invalid: String) async throws {
        let api = ActivityStub()
        api.snapshot = saved()
        let original = api.snapshot, entry = original.entries[0], store = AppStore(activityAPI: api)
        await store.bootstrap()
        store.deleteLog(id: entry.id)
        try await settle { api.pendingDelete != nil }
        let state: ActivitySnapshot = invalid == "still-present" ? original : invalid == "missing-statistics"
            ? .init(entries: [], reviews: [], items: [], universes: [], followerCount: 0) : deletedState(original)
        api.completeDelete(.success(.init(id: invalid == "wrong-id" ? UUID() : entry.id, state: state)))
        try await settle { !store.isDeletingLog }
        #expect(store.diary == original.entries && store.diaryDeleteError != nil && store.pendingDiaryDeletion?.id == entry.id)
    }
}
