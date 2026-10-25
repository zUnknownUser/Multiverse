import Foundation

enum ProductSearch {
    static func matches(_ title: String, query: String) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace })
        return words.allSatisfy { title.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive], locale: .current) != nil }
    }
}

enum DiarySelection: String, CaseIterable {
    case all = "Todos os registros", liked = "Curtidos", rated = "Com nota", rewatched = "Revisitados"

    func includes(_ entry: DiaryEntry) -> Bool {
        switch self {
        case .all: true
        case .liked: entry.liked
        case .rated: entry.rating > 0
        case .rewatched: entry.rewatch
        }
    }
}

struct DiaryQuery: Equatable {
    var text = ""
    var selection: DiarySelection = .all
    var year: Int? = nil

    func entries(_ entries: [DiaryEntry], title: (String) -> String, calendar: Calendar = .current) -> [DiaryEntry] {
        entries.filter {
            selection.includes($0) && (year == nil || calendar.component(.year, from: $0.loggedAt) == year)
                && ProductSearch.matches(title($0.itemId), query: text)
        }.sorted {
            $0.loggedAt == $1.loggedAt ? $0.id.uuidString < $1.id.uuidString : $0.loggedAt > $1.loggedAt
        }
    }
}

enum CommunityEmptyReason: Equatable {
    case search, following, unanswered, scope

    init(filter: CommunityFilter) {
        if !filter.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self = .search }
        else if filter.feed == "following" { self = .following }
        else if filter.feed == "unanswered" { self = .unanswered }
        else { self = .scope }
    }
}
