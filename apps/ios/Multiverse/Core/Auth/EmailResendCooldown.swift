import Foundation
import Observation

/// Local resend feedback; Firebase and the callable functions remain authoritative for rate limits.
@MainActor
@Observable
final class EmailResendCooldown {
    enum Purpose: Hashable { case verification, passwordReset }
    private struct Request: Hashable {
        let purpose: Purpose
        let email: String
        init(_ purpose: Purpose, email: String) {
            self.purpose = purpose
            self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private var deadlines: [Request: Date] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = { .now }) { self.now = now }

    func remaining(for purpose: Purpose, email: String) -> Int {
        guard let deadline = deadlines[Request(purpose, email: email)] else { return 0 }
        return max(0, Int(ceil(deadline.timeIntervalSince(now()))))
    }

    func recordSend(for purpose: Purpose, email: String) {
        let date = now()
        deadlines = deadlines.filter { $0.value > date }
        deadlines[Request(purpose, email: email)] = date.addingTimeInterval(60)
    }

    func clear() { deadlines.removeAll() }
}
