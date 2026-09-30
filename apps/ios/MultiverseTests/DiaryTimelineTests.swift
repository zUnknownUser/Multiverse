import Foundation
import Testing
@testable import Multiverse

struct DiaryTimelineTests {
    private func calendar(_ zone: String = "UTC") throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }
    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
    private func entry(_ value: String) throws -> DiaryEntry {
        DiaryEntry(itemId: "w-wotlk", loggedAt: try date(value), rating: 4)
    }

    @Test func groupsIdenticalMonthsFromDifferentYearsSeparatelyAndSortsEntries() throws {
        let older = try entry("2025-09-30T12:00:00Z")
        let earlier = try entry("2026-09-01T12:00:00Z")
        let later = try entry("2026-09-30T12:00:00Z")
        let groups = DiaryTimeline.months([earlier, older, later], calendar: try calendar())
        #expect(groups.count == 2)
        #expect(groups[0].entries == [later, earlier])
        #expect(groups[1].entries == [older])
        #expect(Set(groups.map(\.id)).count == 2)
    }

    @Test func activityUsesLocalDatesAcrossYearBoundaryWithoutInventingDays() throws {
        let entries = try [entry("2026-12-31T23:30:00Z"), entry("2027-01-01T03:30:00Z"), entry("2025-12-31T12:00:00Z")]
        let end = try date("2027-01-01T05:00:00Z")
        #expect(DiaryTimeline.activityDays(entries, endingAt: end, count: 3, calendar: try calendar()) == [false, true, true])
        #expect(DiaryTimeline.activityDays(entries, endingAt: end, count: 3, calendar: try calendar("America/Manaus")) == [false, true, false])
        #expect(DiaryTimeline.activityDays([], endingAt: end, count: 3) == [false, false, false])
    }

    @Test func activityPreservesCalendarDaysWhenDaylightSavingStarts() throws {
        let entries = try [entry("2026-03-07T17:00:00Z"), entry("2026-03-09T03:30:00Z")]
        let end = try date("2026-03-09T05:00:00Z")
        #expect(DiaryTimeline.activityDays(entries, endingAt: end, count: 3, calendar: try calendar("America/New_York")) == [true, true, false])
    }

    @Test func monthLabelsFollowAppLanguageAndLocalCalendar() throws {
        let instant = try date("2027-01-01T03:30:00Z")
        let local = try calendar("America/Manaus")
        #expect(L10n.date(instant, template: "LLLL", calendar: local, preferredLanguages: ["pt-BR"]).lowercased() == "dezembro")
        #expect(L10n.date(instant, template: "LLLL", calendar: local, preferredLanguages: ["en"]).lowercased() == "december")
        #expect(L10n.date(instant, template: "yyyy", calendar: local, preferredLanguages: ["en"]) == "2026")
        #expect(L10n.date(instant, template: "yyyy", calendar: try calendar(), preferredLanguages: ["en"]) == "2027")
    }

    @Test func timestampAndIdentitySurviveEncoding() throws {
        let original = try entry("2027-02-14T14:35:22Z")
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(DiaryEntry.self, from: data) == original)
    }

    @MainActor @Test func publishingUsesPublicationTimeAndPreservesRepeatedLogs() async throws {
        let repository = MockRepository(startFollowing: false)
        let store = AppStore(repository: repository)
        await store.bootstrap()
        let instant = try date("2027-02-14T14:35:22Z")
        for _ in 0..<2 {
            store.openLog(for: "w-wotlk")
            store.logDraft?.rating = 4
            store.saveLog(at: instant)
        }
        let logs = Array(store.diary.prefix(2))
        #expect(logs.allSatisfy { $0.loggedAt == instant })
        #expect(Set(logs.map(\.id)).count == 2)
        #expect(logs.allSatisfy { $0.rewatch })
        let persisted = try await repository.fetchDiary()
        #expect(persisted.filter { $0.loggedAt == instant }.count == 2)
    }
}
