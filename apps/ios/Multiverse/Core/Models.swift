import SwiftUI

// Espelha 1:1 o arquivo Resources/sample-data.json

struct SampleData: Codable, Sendable {
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
        let url = L10n.resourceURL(named: "sample-data", extension: "json")!
        return try! JSONDecoder().decode(SampleData.self, from: Data(contentsOf: url))
    }
}

struct Universe: Codable, Identifiable, Hashable, Sendable {
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
struct Item: Codable, Identifiable, Hashable, Sendable {
    let id: String, uni: String, type: String, title: String
    let year: FlexString
    let avg: Double
    let canon: String, desc: String
    var logCount: Int? = nil
    var reviewCount: Int? = nil
}

struct User: Codable, Identifiable, Hashable, Sendable {
    let id: String, name: String, handle: String, avatarColor: String, bio: String
    let followers: Int?
    let badgeUniverse: String
}

struct TimelineEntry: Codable, Hashable, Sendable { let era: String, itemId: String, note: String }

struct ReadingOrder: Codable, Identifiable, Hashable, Sendable {
    let id: String, uni: String, title: String, by: String
    let votes: Int
    let steps: [String]
}

struct LoreList: Codable, Identifiable, Hashable, Sendable {
    let id: String, title: String, desc: String
    let likes: Int, comments: Int
    let items: [String]
}

struct Review: Codable, Identifiable, Hashable, Sendable {
    let id: String, user: String, item: String
    var rating: Double
    var text: String
    var spoiler: Bool
    var likes: Int
    var when: String
    var comments: [Comment]
}

struct Comment: Codable, Hashable, Sendable {
    let user: String
    let text: String
    var likes: Int
    /// Ausente no JSON de amostra; os comentários iniciais mostram "1h" (ver AppStore).
    var when: String?
    /// Citação (recurso 5h) — nome de quem foi citado + o trecho citado.
    var quotedAuthor: String?
    var quotedText: String?
}

struct CanonInfo: Codable, Hashable, Sendable { let status: String, note: String }   // Cânone | Variante | Retconado | Contestado
struct StatusColor: Codable, Hashable, Sendable { let bg: String, fg: String }
struct Duel: Codable, Hashable, Sendable { let a: String, b: String, question: String; let baseVotes: [Int] }
struct Me: Codable, Hashable, Sendable { let id: String; let following: [String]; let followers: Int }

struct DiaryEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    let itemId: String
    let loggedAt: Date
    let rating: Double
    var liked = false, rewatch = false
}

/// `year` no JSON às vezes é número (2006) e às vezes texto ("1ª ap. 2002")
struct FlexString: Codable, Hashable, CustomStringConvertible, Sendable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s } else { value = String(try c.decode(Int.self)) }
    }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(value) }
    var description: String { value }
}

// MARK: - Reações (recurso 5a)

enum ReactionType: String, CaseIterable, Codable, Sendable {
    case pow = "POW!", zap = "ZAP!", krak = "KRAK!", heh = "HEH"

    var subtitle: String {
        switch self {
        case .pow: return L10n.text("CONCORDO")
        case .zap: return L10n.text("SURPRESA")
        case .krak: return L10n.text("DISCORDO")
        case .heh: return L10n.text("RI ALTO")
        }
    }

    var color: Color {
        switch self {
        case .pow: return MV.C.marvel
        case .zap: return MV.C.dc
        case .krak: return MV.C.wow
        case .heh: return MV.C.card
        }
    }

    var textColor: Color { self == .heh ? MV.C.ink : MV.C.card }
}

// MARK: - Mensagens e cartas (recursos 5b–5d, 5g)

struct Conversation: Codable, Identifiable, Hashable, Sendable {
    var id: String { userID }
    let userID: String
    var lastPreview: String
    var lastWhen: String
    var unreadCount: Int
    /// Cai em "Pedidos" quando a pessoa ainda não é seguida de volta.
    var isRequest: Bool
}

enum CardKind: String, Codable, Sendable {
    case text, workCard, duelChallenge
}

struct DuelChallengePayload: Codable, Hashable, Sendable {
    let itemAID: String
    let itemBID: String
    let question: String
    let wager: String
    var chooserChoice: Int?    // lado que quem desafiou escolheu (some com o resultado)
    var responderChoice: Int?  // lado que "eu" escolhi
}

struct Message: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let conversationID: String
    let senderID: String
    let when: String
    let kind: CardKind
    var text: String?
    var itemID: String?
    var duelChallenge: DuelChallengePayload?
}

// MARK: - Salas por obra (recursos 5e, 5i, 5f)

struct Room: Codable, Identifiable, Hashable, Sendable {
    var id: String { itemID }
    let itemID: String
    let segments: [String]
    let onlineCount: Int
}

struct RoomMessage: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let itemID: String
    let segmentIndex: Int
    let userID: String
    let text: String
    let when: String
}

/// "Estreia ao vivo" — recurso 5f. Evento único de demonstração; ver `LivePremiereView`.
struct LiveEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let itemID: String
    let question: String
    let viewerCount: Int
    let durationSeconds: Int
}

// MARK: - Escudo de spoiler

/// Índice do usuário na timeline de um universo — tudo que vem depois fica escondido.
struct ShieldPoint: Codable, Hashable, Sendable {
    let uni: String
    var timelineIndex: Int
}

// MARK: - Clubes de maratona

struct ClubWeek: Codable, Hashable, Sendable {
    let week: Int
    let itemID: String
    let totalUnits: Int
    let unitLabel: String        // "Cap." / "Ep."
    let paceLabel: String        // "Livro · 400 páginas · ≈57 por dia"
    let segments: [String]       // rótulos das abas de discussão, ex.: ["Cap. 1–8", "Cap. 9–16", "Final"]
}

struct Club: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let uni: String
    let orderID: String
    let memberIDs: [String]
    let weeks: [ClubWeek]
    let currentWeek: Int
}

struct ClubMessage: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let clubID: String
    let week: Int
    let segment: String
    let userID: String
    let text: String
    let when: String
    var hearts: Int
    var pows: Int
    /// Capítulo/episódio a que a mensagem se refere — escondida se à frente do progresso do usuário.
    let aboutUnit: Int
}

// MARK: - Teorias

enum TheoryStatus: String, Codable, Sendable {
    case open = "aberta", confirmed = "confirmada", refuted = "refutada"
}

struct Theory: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let userID: String
    let uni: String
    let text: String
    var status: TheoryStatus
    let postedDaysAgo: Int
    /// Base de votos "Plausível" / "Viajou" — o resultado de uma teoria é sempre público.
    let plausibleBase: Int
    let travelBase: Int
    /// Item do catálogo onde a teoria deve se resolver (ex.: "Resolve em: Guerras Secretas").
    let resolvesAtItemID: String?
    /// Título livre da fonte que confirmou/refutou (nem sempre é um item do catálogo, ex.: "The War Within").
    let resolutionTitle: String?
    let resolutionNote: String?       // "Cinemática 3 · marcada por 3 revisores"
    let accuracyBefore: Int?
    let accuracyAfter: Int?
}

// MARK: - Previsões

struct PredictionQuestion: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let points: Int
    /// Múltipla escolha quando presente; slider (0...10, meio-a-meio 1★–5★) quando `nil`.
    let options: [String]?
    let correctOptionIndex: Int?
    let revealed: Bool
}

struct PredictionEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let uni: String
    let title: String
    let closesAt: Date
    let questions: [PredictionQuestion]
}

// MARK: - Denúncia

enum ReportReason: String, CaseIterable, Codable, Sendable {
    case spoiler = "Spoiler sem aviso"
    case offensive = "Ofensivo ou tóxico"
    case spam = "Spam ou golpe"
    case wrongCanon = "Cânone errado de propósito"
    case other = "Outro motivo"

    var subtitle: String {
        switch self {
        case .spoiler: return L10n.text("Não marcou como spoiler")
        case .offensive: return L10n.text("Ataques, preconceito, assédio")
        case .spam: return L10n.text("Links, divulgação")
        case .wrongCanon: return L10n.text("Desinformação sobre a lore")
        case .other: return ""
        }
    }
}

// MARK: - Sugerir correção

enum CorrectionChangeType: String, CaseIterable, Codable, Sendable {
    case canonStatus = "Status de cânone", timeline = "Linha do tempo", connections = "Conexões", data = "Dados"
}

struct CorrectionSuggestion: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let itemID: String
    let userID: String
    let changeType: CorrectionChangeType
    let fromValue: String
    let toValue: String
    let source: String
    let reasoning: String
    var approverIDs: [String]
    let approvalsNeeded: Int
}

// MARK: - Onde assistir

struct WatchOption: Codable, Identifiable, Hashable, Sendable {
    var id: String { service }
    let service: String
    let initials: String
    let colorHex: String
    let note: String
    let actionLabel: String
}

struct ReadFirstOption: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let colorHex: String
    let note: String
    let actionLabel: String
}

struct WatchAvailability: Codable, Hashable, Sendable {
    let itemID: String
    let options: [WatchOption]
    let readFirst: [ReadFirstOption]
}

// MARK: - Dados dos recursos novos (Resources/recursos-data.json)

struct RecursosData: Codable, Sendable {
    let clubs: [Club]
    let clubMessages: [ClubMessage]
    let theories: [Theory]
    let predictionEvents: [PredictionEvent]
    let watchAvailability: [WatchAvailability]
    let correctionSuggestions: [CorrectionSuggestion]
    let conversations: [Conversation]
    let messages: [Message]
    let rooms: [Room]
    let roomMessages: [RoomMessage]
    let liveEvent: LiveEvent

    static func load() -> RecursosData {
        let url = L10n.resourceURL(named: "recursos-data", extension: "json")!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(RecursosData.self, from: Data(contentsOf: url))
    }
}
