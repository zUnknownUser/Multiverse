import Foundation

/// An account can log out and back in with the same UID. Each binding still needs
/// its own lifetime so delayed requests cannot read, write or close the new session.
@MainActor @Observable
final class SessionLifecycle {
    private(set) var generation = UUID()
    @ObservationIgnored var onFailure: ((AuthError) -> Void)?

    func invalidate() { generation = UUID() }
    func check(_ generation: UUID) throws {
        try Task.checkCancellation()
        guard generation == self.generation else { throw CancellationError() }
    }
    func report(_ error: any Error, generation: UUID) {
        guard generation == self.generation, let error = error as? AuthError,
              [.sessionExpired, .accountDisabled, .deletionPending].contains(error) else { return }
        onFailure?(error)
    }
}
