import Foundation

@MainActor
protocol CatalogAPI: Sendable {
    var usesPagination: Bool { get }
    func fetchCatalog() async throws -> CatalogSnapshot
    func fetchBootstrap() async throws -> CatalogSnapshot
    func fetchItems(query: CatalogQuery, after: String?) async throws -> CatalogItemPage
    func fetchSeries(universe: String?, after: String?) async throws -> CatalogSeriesPage
    func fetchSeries(id: String) async throws -> CatalogSeriesRecord
    func resolveItems(ids: [String]) async throws -> CatalogResolution
}

extension CatalogAPI {
    var usesPagination: Bool { false }
    func fetchBootstrap() async throws -> CatalogSnapshot { try await fetchCatalog() }
    func fetchItems(query: CatalogQuery, after: String?) async throws -> CatalogItemPage { throw CatalogError.unavailable }
    func fetchSeries(universe: String?, after: String?) async throws -> CatalogSeriesPage { throw CatalogError.unavailable }
    func fetchSeries(id: String) async throws -> CatalogSeriesRecord { throw CatalogError.unavailable }
    func resolveItems(ids: [String]) async throws -> CatalogResolution { throw CatalogError.unavailable }
}

struct CatalogQuery: Hashable, Sendable {
    var text = ""
    var category = "all"
    var universe: String? = nil
    var series: String? = nil
}
struct CatalogTaskKey: Hashable { let query: CatalogQuery; let generation: Int }

struct CatalogItemPage: Codable, Sendable {
    let locale: String
    let total: Int
    let items: [Item]
    let nextCursor: String?
}
struct CatalogSeriesRecord: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let year: Int
    let universe: String
    let total: Int
}
struct CatalogSeriesPage: Codable, Sendable {
    let locale: String
    let total: Int
    let series: [CatalogSeriesRecord]
    let nextCursor: String?
}
struct CatalogResolution: Codable, Sendable {
    let locale: String
    let items: [Item]
    let missingIDs: [String]
}
struct CatalogReference: Codable, Sendable {
    let id: String
    let uni: String
    let type: String
    var seriesID: String? = nil
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
    var discoveryIDs: [String]? = nil
    var onboardingIDs: [String]? = nil
    var topRatedIDs: [String]? = nil
    var aggregateAverage: Double? = nil

    func validate() throws {
        guard !universes.isEmpty else { throw CatalogError.empty }
        let itemIDs = Set(items.map(\.id))
        for selection in [discoveryIDs, onboardingIDs, topRatedIDs].compactMap({ $0 }) {
            guard Set(selection).count == selection.count, selection.allSatisfy(itemIDs.contains) else { throw CatalogError.unavailable }
        }
        if let aggregateAverage, !(0...5).contains(aggregateAverage) { throw CatalogError.unavailable }
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

    var usesPagination: Bool { true }
    func fetchCatalog() async throws -> CatalogSnapshot { try await snapshot(path: "catalog") }
    func fetchBootstrap() async throws -> CatalogSnapshot { try await snapshot(path: "catalog/bootstrap") }
    private func snapshot(path: String) async throws -> CatalogSnapshot {
        let snapshot: CatalogSnapshot = try await request(path)
        try snapshot.validate()
        return snapshot
    }
    func fetchItems(query: CatalogQuery, after: String?) async throws -> CatalogItemPage {
        var values = [URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "q", value: query.text), URLQueryItem(name: "category", value: query.category)]
        if let universe = query.universe { values.append(.init(name: "universe", value: universe)) }
        if let series = query.series { values.append(.init(name: "series", value: series)) }
        if let after { values.append(.init(name: "after", value: after)) }
        return try await request("catalog/items", query: values)
    }
    func fetchSeries(universe: String?, after: String?) async throws -> CatalogSeriesPage {
        var values = [URLQueryItem(name: "limit", value: "20")]
        if let universe { values.append(.init(name: "universe", value: universe)) }
        if let after { values.append(.init(name: "after", value: after)) }
        return try await request("catalog/series", query: values)
    }
    func fetchSeries(id: String) async throws -> CatalogSeriesRecord { try await request("catalog/series/" + id) }
    func resolveItems(ids: [String]) async throws -> CatalogResolution {
        try await request("catalog/resolve", query: [.init(name: "ids", value: ids.joined(separator: ","))])
    }
    private func request<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard let baseURL else { throw AuthError.apiNotConfigured }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw CatalogError.unavailable }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(AppEnvironment.current.rawValue, forHTTPHeaderField: "X-Multiverse-Environment")
        request.setValue(L10n.language(), forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await transport.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw CatalogError.unavailable }
            if let environment = http.value(forHTTPHeaderField: "X-Multiverse-Environment"), environment != AppEnvironment.current.rawValue { throw CatalogError.unavailable }
            return try JSONDecoder().decode(T.self, from: data)
        } catch is CancellationError { throw CancellationError() }
        catch let error as CatalogError { throw error }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw CatalogError.networkFailure(error)
        }
        catch { throw CatalogError.unavailable }
    }
}
