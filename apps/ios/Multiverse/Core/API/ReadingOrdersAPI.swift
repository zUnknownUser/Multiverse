import Foundation

struct ReadingOrdersSnapshot: Decodable, Sendable {
    let version: Int
    let locale: String
    let orders: [ReadingOrder]
    func validate() throws {
        guard version >= 0, ["pt-BR", "en"].contains(locale), Set(orders.map(\.id)).count == orders.count,
              orders.allSatisfy({ !$0.id.isEmpty && ["marvel", "dc"].contains($0.uni) && !$0.title.isEmpty && $0.by == "multiverse" && !($0.description ?? "").isEmpty && $0.votes >= 0 && ($0.followers ?? -1) >= 0 && $0.following != nil && $0.voted != nil && !$0.steps.isEmpty && $0.steps.count <= 200 && Set($0.steps).count == $0.steps.count && $0.steps.allSatisfy({ !$0.isEmpty }) }) else { throw ReadingOrdersError.invalid }
    }
}
struct ReadingOrderMutation: Encodable, Equatable, Sendable {
    let mutationID: String
    let version: Int
    let orderID: String
    let action: String
    let enabled: Bool
}
struct ReadingOrderReceipt: Decodable, Sendable {
    let mutationID: String
    let appliedVersion: Int
    let state: ReadingOrdersSnapshot
}
@MainActor protocol ReadingOrdersAPI: Sendable {
    func fetchReadingOrders() async throws -> ReadingOrdersSnapshot
    func mutateReadingOrder(_ input: ReadingOrderMutation) async throws -> ReadingOrderReceipt
}
extension AccountAPIClient: ReadingOrdersAPI {
    func fetchReadingOrders() async throws -> ReadingOrdersSnapshot { try await request("me/reading-orders") }
    func mutateReadingOrder(_ input: ReadingOrderMutation) async throws -> ReadingOrderReceipt {
        try await request("me/reading-orders", method: "PUT", body: JSONEncoder().encode(input))
    }
}
enum ReadingOrdersError: LocalizedError, Equatable {
    case unavailable, stale, conflict, limit, invalid
    var errorDescription: String? {
        switch self {
        case .unavailable: L10n.text("Esta ordem não está disponível. Atualize para ver os percursos atuais.")
        case .stale: L10n.text("Suas ordens mudaram em outro dispositivo. Atualize e tente novamente.")
        case .conflict: L10n.text("Não foi possível confirmar essa alteração. Atualize suas ordens.")
        case .limit: L10n.text("Você alterou muitas ordens. Tente novamente mais tarde.")
        case .invalid: L10n.text("Não conseguimos atualizar as ordens de leitura. Tente novamente.")
        }
    }
}
