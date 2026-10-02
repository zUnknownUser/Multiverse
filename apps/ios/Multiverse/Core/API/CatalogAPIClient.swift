import Foundation

@MainActor
protocol CatalogAPI: Sendable {
    func fetchCatalog() async throws -> CatalogSnapshot
}

struct UpcomingUniverse: Codable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct CatalogSnapshot: Codable, Sendable {
    let version: Int
    let locale: String
    let universes: [Universe]
    let comingSoon: [UpcomingUniverse]
    let items: [Item]

    func validate() throws {
        guard !universes.isEmpty else { throw CatalogError.empty }
        let ids = Set(universes.map(\.id))
        let upcomingIDs = Set(comingSoon.map(\.id))
        guard version == 1, ["pt-BR", "en"].contains(locale),
              ids.count == universes.count, Set(items.map(\.id)).count == items.count,
              upcomingIDs.count == comingSoon.count, ids.isDisjoint(with: upcomingIDs),
              universes.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && $0.total >= 0 && $0.members >= 0 }),
              items.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty && ids.contains($0.uni) && ($0.series?.isValid ?? true) }) else {
            throw CatalogError.unavailable
        }
    }
}

enum CatalogError: LocalizedError, Equatable {
    case unavailable, offline, timedOut, empty, changed
    var title: String {
        switch self {
        case .empty: return L10n.text("Catálogo em preparação")
        case .offline: return L10n.text("Sem conexão")
        case .timedOut: return L10n.text("A conexão demorou mais que o esperado")
        case .changed: return L10n.text("Catálogo atualizado")
        case .unavailable: return L10n.text("Não conseguimos carregar o catálogo")
        }
    }
    var errorDescription: String? {
        switch self {
        case .unavailable: return L10n.text("O serviço está indisponível no momento. Tente novamente em instantes.")
        case .offline: return L10n.text("Confira sua conexão com a internet e tente novamente.")
        case .timedOut: return L10n.text("O catálogo não respondeu a tempo. Tente novamente.")
        case .empty: return L10n.text("Ainda não há universos disponíveis. Volte em instantes para conferir as novidades.")
        case .changed: return L10n.text("O catálogo mudou. Atualize para continuar.")
        }
    }
    static func networkFailure(_ error: URLError) -> CatalogError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return .offline
        case .timedOut: return .timedOut
        default: return .unavailable
        }
    }
}

@MainActor
final class CatalogAPIClient: CatalogAPI {
    private let baseURL: URL?
    private let transport: URLSession
    init(baseURL: URL? = AccountAPIClient.configuredURL(), transport: URLSession = .shared) {
        self.baseURL = baseURL
        self.transport = transport
    }

    func fetchCatalog() async throws -> CatalogSnapshot {
        guard let baseURL else { throw AuthError.apiNotConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent("catalog"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(L10n.language(), forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await transport.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw CatalogError.unavailable }
            let snapshot = try JSONDecoder().decode(CatalogSnapshot.self, from: data)
            try snapshot.validate()
            return snapshot
        } catch is CancellationError { throw CancellationError() }
        catch let error as CatalogError { throw error }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw CatalogError.networkFailure(error)
        }
        catch { throw CatalogError.unavailable }
    }
}
