import SwiftUI

// Espelha 1:1 o arquivo data/sample-data.json

struct SampleData: Codable {
    let universes: [Universe]
    let items: [Item]
    let users: [User]
    let badgeNames: [String: String]          // wow → "Azeroth", marvel → "Terra-616", dc → "Multi-DC"
    let connections: [String: [String]]       // itemId → [itemId]
    let timelines: [String: [TimelineEntry]]  // universeId → entradas em ordem canônica
    let readingOrders: [ReadingOrder]
    let lists: [LoreList]
    let reviews: [Review]
    let genericReviewTexts: [String]
    let canonStatus: [String: CanonInfo]      // itemId → status (default: "Cânone")
    let canonStatusColors: [String: StatusColor]
    let duels: [Duel]
    let me: Me

    static func load() -> SampleData {
        let url = Bundle.main.url(forResource: "sample-data", withExtension: "json")!
        return try! JSONDecoder().decode(SampleData.self, from: Data(contentsOf: url))
    }
}

struct Universe: Codable, Identifiable, Hashable {
    let id: String, name: String
    let c: String, c2: String, ink: String   // cor principal, variante escura, cor do texto sobre a principal
    let track: String                        // rgba() da trilha de progresso sobre a cor (ver Theme)
    let canon: String, tagline: String
    let base: Int, total: Int, members: Int, live: Int
    var color: Color { Color(hex: c) }
    var color2: Color { Color(hex: c2) }
    var inkColor: Color { Color(hex: ink) }
    var trackColor: Color { ink == "#16130F" ? MV.C.ink.opacity(0.2) : MV.C.card.opacity(0.35) }
}

/// Obra, personagem ou evento. type ∈ HQ, Filme, Série, Jogo, Livro, Personagem, Evento
struct Item: Codable, Identifiable, Hashable {
    let id: String, uni: String, type: String, title: String
    let year: FlexString
    let avg: Double
    let canon: String, desc: String
}

struct User: Codable, Identifiable, Hashable {
    let id: String, name: String, handle: String, avatarColor: String, bio: String
    let followers: Int?
    let badgeUniverse: String
}

struct TimelineEntry: Codable, Hashable { let era: String, itemId: String, note: String }

struct ReadingOrder: Codable, Identifiable, Hashable {
    let id: String, uni: String, title: String, by: String
    let votes: Int
    let steps: [String]
}

struct LoreList: Codable, Identifiable, Hashable {
    let id: String, title: String, desc: String
    let likes: Int, comments: Int
    let items: [String]
}

struct Review: Codable, Identifiable, Hashable {
    let id: String, user: String, item: String
    var rating: Double
    var text: String
    var spoiler: Bool
    var likes: Int
    var when: String
    var comments: [Comment]
}

struct Comment: Codable, Hashable { let user: String; let text: String; var likes: Int }

struct CanonInfo: Codable, Hashable { let status: String, note: String }   // Cânone | Variante | Retconado | Contestado
struct StatusColor: Codable, Hashable { let bg: String, fg: String }
struct Duel: Codable, Hashable { let a: String, b: String, question: String; let baseVotes: [Int] }
struct Me: Codable, Hashable { let id: String; let following: [String]; let followers: Int }

struct DiaryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    let itemId: String, day: Int, month: String
    let rating: Double
    var liked = false, rewatch = false
}

/// `year` no JSON às vezes é número (2006) e às vezes texto ("1ª ap. 2002")
struct FlexString: Codable, Hashable, CustomStringConvertible {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s } else { value = String(try c.decode(Int.self)) }
    }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(value) }
    var description: String { value }
}
