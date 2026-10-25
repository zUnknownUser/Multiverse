import Foundation
import Testing
@testable import Multiverse

@MainActor
struct ProductImprovementsTests {
    @Test func draftsSurviveReopeningAndStayScopedToAccountAndEnvironment() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FileLogDraftStorage(userID: "one", environment: .staging, directory: directory)
        let first = AppStore(draftStorage: storage)
        await first.bootstrap()
        first.openLog(for: "m-civil")
        first.logDraft?.text = "Uma opinião ainda privada"
        first.logDraft?.rating = 4.5
        first.logDraft?.spoiler = true
        first.logDraft?.loggedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let draft = try #require(first.logDraft)
        first.closeLog()
        #expect(first.logDraft == nil)
        let reopened = AppStore(draftStorage: storage)
        await reopened.bootstrap()
        #expect(reopened.savedLogDraft == draft)
        reopened.openLog(for: "m-ironman")
        #expect(reopened.logDraft == draft) // Opening another work never destroys unsent text.
        #expect(try FileLogDraftStorage(userID: "two", environment: .staging, directory: directory).load() == nil)
        #expect(try FileLogDraftStorage(userID: "one", environment: .production, directory: directory).load() == nil)
        let values = try storage.file.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        reopened.discardLogDraft()
        #expect(try storage.load() == nil)
        #expect(reopened.savedLogDraft == nil)
    }

    @Test func damagedDraftIsReportedWithoutBreakingStartup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FileLogDraftStorage(userID: "one", environment: .staging, directory: directory)
        try storage.save(LogDraft(text: "before"))
        try Data("invalid".utf8).write(to: storage.file)
        let store = AppStore(draftStorage: storage)
        await store.bootstrap()
        #expect(store.draftStorageError != nil)
        #expect(store.savedLogDraft == nil)
        store.openLogBlank()
        store.logDraft?.text = "new draft"
        #expect(try storage.load()?.text == "new draft")
        #expect(store.draftStorageError == nil)
    }

    @Test func failedDraftWriteKeepsTextInMemoryAndShowsRecoveryWarning() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let storage = FileLogDraftStorage(userID: "one", environment: .staging, directory: file)
        let store = AppStore(draftStorage: storage)
        await store.bootstrap()
        store.openLogBlank()
        store.logDraft?.text = "Still available in this session"
        #expect(store.draftStorageError != nil)
        store.closeLog()
        store.openLogBlank()
        #expect(store.logDraft?.text == "Still available in this session")
    }

    @Test func profileQuotaSuggestsWaitingInsteadOfDeletingContent() {
        let error = MultiverseAPIErrorMapper().responseError(code: "IMAGE_LIMIT", status: 429, path: "me/profile/details")
        #expect(error as? AuthError == .tooManyRequests)
    }

    @Test func diarySearchCombinesTextYearAndStatusWithoutLosingHistory() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let entries = [DiaryEntry(itemId: "one", loggedAt: date, rating: 4, liked: true, rewatch: true),
                       DiaryEntry(itemId: "two", loggedAt: date, rating: 0, liked: false, rewatch: false),
                       DiaryEntry(itemId: "one", loggedAt: date.addingTimeInterval(-86400), rating: 5, liked: true)]
        let query = DiaryQuery(text: "  heroi   ACAO ", selection: .liked, year: 2026)
        let found = query.entries(entries, title: { $0 == "one" ? "Herói em Ação" : "Outro" }, calendar: calendar)
        #expect(found.map(\.id) == [entries[0].id])
        #expect(DiaryQuery().entries(entries, title: { $0 }).count == 3)
        #expect(ProductSearch.matches("Herói", query: "   "))
        #expect(!ProductSearch.matches("Herói", query: "vilão"))
        #expect(DiarySelection.rated.includes(entries[0]))
        #expect(!DiarySelection.rated.includes(entries[1]))
        #expect(DiarySelection.rewatched.includes(entries[0]))
    }

    @Test func emptyCommunityExplainsSearchBeforeFeedAndPreservesScope() {
        #expect(CommunityEmptyReason(filter: .init(search: "hero", feed: "following")) == .search)
        #expect(CommunityEmptyReason(filter: .init(feed: "following")) == .following)
        #expect(CommunityEmptyReason(filter: .init(feed: "unanswered")) == .unanswered)
        #expect(CommunityEmptyReason(filter: .init(universe: "dc", search: "  ")) == .scope)
    }
}
