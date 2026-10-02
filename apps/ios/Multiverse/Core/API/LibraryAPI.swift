import Foundation

struct PersonalList: Codable, Identifiable, Sendable, Equatable {
    let id: String; let title: String; let description: String; let itemIDs: [String]
    let createdAt: Date; let updatedAt: Date
}
struct LibrarySnapshot: Codable, Sendable {
    let version: Int; let wantedIDs: [String]; let favoriteIDs: [String]; let lists: [PersonalList]
    func validate() throws {
        guard version >= 0, Set(wantedIDs).count == wantedIDs.count, Set(favoriteIDs).count == favoriteIDs.count,
              Set(lists.map(\.id)).count == lists.count, lists.count <= 50,
              lists.allSatisfy({ UUID(uuidString: $0.id) != nil && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Set($0.itemIDs).count == $0.itemIDs.count && $0.itemIDs.count <= 200 }) else { throw LibraryError.invalid }
    }
}
struct LibraryMutation: Codable, Sendable {
    let mutationID: String; let version: Int; let action: String
    var listID: String?; var itemID: String?; var enabled: Bool?; var title: String?; var description: String?
}
struct LibraryReceipt: Codable, Sendable { let mutationID: String; let appliedVersion: Int; let state: LibrarySnapshot }
@MainActor protocol LibraryAPI: Sendable {
    func fetchLibrary() async throws -> LibrarySnapshot
    func mutateLibrary(_ input: LibraryMutation) async throws -> LibraryReceipt
}
extension AccountAPIClient {
    func fetchLibrary() async throws -> LibrarySnapshot { try await request("me/library") }
    func mutateLibrary(_ input: LibraryMutation) async throws -> LibraryReceipt {
        try await request("me/library", method: "PUT", body: JSONEncoder().encode(input))
    }
}
enum LibraryError: LocalizedError, Equatable {
    case invalid, stale, unavailable, conflict, listLimit, itemLimit, savedLimit
    var errorDescription: String? {
        switch self {
        case .invalid: L10n.text("Não foi possível confirmar a alteração na biblioteca. Tente novamente.")
        case .stale: L10n.text("Sua biblioteca mudou em outro dispositivo. Confira os dados atualizados e tente novamente.")
        case .unavailable: L10n.text("Esta lista não está mais disponível.")
        case .conflict: L10n.text("Este envio já foi usado. Atualize a biblioteca antes de tentar novamente.")
        case .listLimit: L10n.text("Você pode manter até 50 listas pessoais.")
        case .itemLimit: L10n.text("Cada lista pode conter até 200 obras.")
        case .savedLimit: L10n.text("Sua biblioteca pode guardar até 1.000 obras entre desejos e favoritos.")
        }
    }
}
