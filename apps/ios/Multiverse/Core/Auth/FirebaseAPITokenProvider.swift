import Foundation
import FirebaseAuth

struct FirebaseAPITokenProvider: APITokenProvider {
    var userID: String? { Auth.auth().currentUser?.uid }
    func token(forceRefresh: Bool) async throws -> String {
        guard let user = Auth.auth().currentUser else { throw AuthError.sessionExpired }
        do { return try await user.getIDToken(forcingRefresh: forceRefresh) }
        catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            let nsError = error as NSError
            guard nsError.domain == AuthErrorDomain else { throw error }
            let code = AuthErrorCode(rawValue: nsError.code)
            switch code {
            case .userTokenExpired, .invalidUserToken, .userNotFound: throw AuthError.sessionExpired
            case .userDisabled: throw AuthError.accountDisabled
            default: throw error
            }
        }
    }
}

