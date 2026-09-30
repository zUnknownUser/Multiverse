@MainActor
protocol APITokenProvider: Sendable {
    var userID: String? { get }
    func token(forceRefresh: Bool) async throws -> String
}
