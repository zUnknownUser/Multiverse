import Foundation

struct DuelCandidate: Decodable, Identifiable, Sendable {
    let id: String
    let postID: String?
    let title: String
    let status: String
    let scheduledOn: String?
    let publishedPostID: String?
    let reasonCode: String?
    var canWithdraw: Bool { ["pending", "approved"].contains(status) && postID != nil }
    var statusLabel: String {
        switch status {
        case "pending": return L10n.text("EM REVISÃO")
        case "approved": return scheduledOn == nil ? L10n.text("NA FILA EDITORIAL") : L10n.text("AGENDADO")
        case "published": return L10n.text("PUBLICADO NA ARENA")
        case "withdrawn": return L10n.text("SUGESTÃO RETIRADA")
        default: return L10n.text("NÃO SELECIONADO")
        }
    }
    var explanation: String? {
        switch reasonCode {
        case "source_changed": return L10n.text("A publicação foi alterada ou deixou de estar disponível. Crie um novo duelo para sugerir outra ideia.")
        case "duplicate": return L10n.text("Essa pergunta já passou pela arena. Experimente uma nova ideia.")
        case "editorial_decision": return L10n.text("Essa sugestão não entrou na seleção editorial. Você pode propor outras ideias.")
        default: return nil
        }
    }
    func validate() throws {
        guard UUID(uuidString: id) != nil, !title.isEmpty, ["pending","approved","published","withdrawn","rejected"].contains(status),
              postID.map({ UUID(uuidString: $0) != nil }) ?? true,
              publishedPostID.map({ UUID(uuidString: $0) != nil }) ?? true else { throw SocialError.invalid }
    }
}
struct DuelCandidateReceipt: Decodable, Sendable { let candidate: DuelCandidate? }
struct DuelCandidatePage: Decodable, Sendable { let items: [DuelCandidate] }
@MainActor protocol DuelCurationAPI: Sendable {
    func duelCandidate(post: String) async throws -> DuelCandidateReceipt
    func suggestDuel(post: String) async throws -> DuelCandidateReceipt
    func withdrawDuel(post: String) async throws -> DuelCandidateReceipt
    func myDuelCandidates() async throws -> DuelCandidatePage
}
extension AccountAPIClient: DuelCurationAPI {
    func duelCandidate(post: String) async throws -> DuelCandidateReceipt { try await request("community/duel-candidates/posts/" + post) }
    func suggestDuel(post: String) async throws -> DuelCandidateReceipt { try await request("community/duel-candidates/posts/" + post, method: "PUT") }
    func withdrawDuel(post: String) async throws -> DuelCandidateReceipt { try await request("community/duel-candidates/posts/" + post, method: "DELETE") }
    func myDuelCandidates() async throws -> DuelCandidatePage { try await request("community/duel-candidates/mine") }
}

enum DuelCurationError: LocalizedError {
    case ineligible, limit, unavailable
    var errorDescription: String? {
        switch self {
        case .ineligible: return L10n.text("Só é possível sugerir um duelo seu, disponível, sem spoilers e fora de clubes.")
        case .limit: return L10n.text("Você pode manter até 3 sugestões ativas e enviar até 3 a cada 24 horas.")
        case .unavailable: return L10n.text("Essa sugestão não está mais disponível para alteração. Atualize a lista.")
        }
    }
}
