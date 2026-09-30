import Foundation

struct DiaryMonth: Identifiable {
    let start: Date
    let entries: [DiaryEntry]
    var id: Date { start }
}

/// Groups timestamps using the user's calendar and time zone, never translated month names.
enum DiaryTimeline {
    static func months(_ entries: [DiaryEntry], calendar: Calendar = .current) -> [DiaryMonth] {
        var groups: [Date: [DiaryEntry]] = [:]
        for entry in entries {
            guard let start = calendar.dateInterval(of: .month, for: entry.loggedAt)?.start else { continue }
            groups[start, default: []].append(entry)
        }
        return groups.keys.sorted(by: >).map { start in
            DiaryMonth(start: start, entries: groups[start, default: []].sorted { $0.loggedAt > $1.loggedAt })
        }
    }

    /// Oldest to newest, including today. Calendar arithmetic preserves days across DST changes.
    static func activityDays(
        _ entries: [DiaryEntry], endingAt date: Date = .now, count: Int = 105, calendar: Calendar = .current
    ) -> [Bool] {
        guard count > 0 else { return [] }
        let seenDays = Set(entries.map { calendar.startOfDay(for: $0.loggedAt) })
        let end = calendar.startOfDay(for: date)
        return (0..<count).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { return false }
            return seenDays.contains(day)
        }
    }
}
