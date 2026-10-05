import Foundation

@MainActor protocol AuthenticatedRequesting: Sendable {
    func request<Response: Decodable>(_ path: String, method: String, body: Data?, query: [URLQueryItem], timeout: TimeInterval) async throws -> Response
}

/// Owns account-bound authorization, refresh-once, cancellation and HTTP decoding.
@MainActor final class AuthenticatedHTTPClient: AuthenticatedRequesting {
    private let errors: any APIErrorMapping
    private struct APIError: Decodable { let code: String? }
    private let baseURL: URL?
    private let tokens: any APITokenProvider
    private let transport: URLSession
    private let expectedUserID: String?
    private let lifecycle: SessionLifecycle?
    private let boundGeneration: UUID?

    init(baseURL: URL?, tokens: any APITokenProvider = FirebaseAPITokenProvider(), transport: URLSession = .shared, expectedUserID: String? = nil, errors: any APIErrorMapping = MultiverseAPIErrorMapper(), lifecycle: SessionLifecycle? = nil) {
        self.lifecycle = lifecycle
        self.boundGeneration = expectedUserID == nil ? nil : lifecycle?.generation
        self.errors = errors
        self.baseURL = baseURL
        self.tokens = tokens
        self.transport = transport
        self.expectedUserID = expectedUserID
    }
    func request<Response: Decodable>(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = [], timeout: TimeInterval = 20) async throws -> Response {
        let generation = boundGeneration ?? lifecycle?.generation
        do {
            if let generation { try lifecycle?.check(generation) }
            return try await perform(path, method: method, body: body, query: query, timeout: timeout, generation: generation)
        } catch {
            if let generation {
                try lifecycle?.check(generation)
                lifecycle?.report(error, generation: generation)
            }
            throw error
        }
    }
    private func perform<Response: Decodable>(_ path: String, method: String, body: Data?, query: [URLQueryItem], timeout: TimeInterval, generation: UUID?) async throws -> Response {
        guard let baseURL else { throw AuthError.apiNotConfigured }
        guard let uid = tokens.userID, expectedUserID == nil || uid == expectedUserID else { throw AuthError.sessionExpired }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        for attempt in 0...1 {
            var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer " + (try await tokens.token(forceRefresh: attempt == 1)), forHTTPHeaderField: "Authorization")
            if let generation { try lifecycle?.check(generation) }
            guard tokens.userID == uid else { throw AuthError.sessionExpired }
            request.setValue(L10n.language(), forHTTPHeaderField: "Accept-Language")
            let data: Data
            let response: URLResponse
            do { (data, response) = try await transport.data(for: request) }
            catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                throw errors.networkError(error, path: path)
            }
            try Task.checkCancellation()
            if let generation { try lifecycle?.check(generation) }
            guard tokens.userID == uid else { throw AuthError.sessionExpired }
            guard let http = response as? HTTPURLResponse else { throw AuthError.apiUnavailable }
            if http.statusCode == 401 && attempt == 0 { continue }
            if (200..<300).contains(http.statusCode) {
                do {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .custom { decoder in
                        let value = try decoder.singleValueContainer().decode(String.self)
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        if let date = formatter.date(from: value) { return date }
                        formatter.formatOptions = [.withInternetDateTime]
                        guard let date = formatter.date(from: value) else { throw AuthError.apiUnavailable }
                        return date
                    }
                    return try decoder.decode(Response.self, from: data)
                }
                catch { throw AuthError.apiUnavailable }
            }
            let code = (try? JSONDecoder().decode(APIError.self, from: data))?.code
            throw errors.responseError(code: code, status: http.statusCode, path: path)
        }
        throw AuthError.sessionExpired
    }
}
