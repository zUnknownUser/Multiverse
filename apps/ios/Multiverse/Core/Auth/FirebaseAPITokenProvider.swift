import FirebaseAuth

struct FirebaseAPITokenProvider: APITokenProvider {
    var userID: String? { Auth.auth().currentUser?.uid }
    func token(forceRefresh: Bool) async throws -> String {
        guard let user = Auth.auth().currentUser else { throw AuthError.sessionExpired }
        return try await user.getIDToken(forcingRefresh: forceRefresh)
    }
}

