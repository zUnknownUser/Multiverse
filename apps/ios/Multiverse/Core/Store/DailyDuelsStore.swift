import Foundation
import Observation

@MainActor @Observable final class DailyDuelsStore {
    let api: any DailyDuelsAPI
    private(set) var hub: DailyDuelHub?
    private(set) var busy = false
    private(set) var voting = false
    private(set) var error: String?
    private(set) var clockOffset: TimeInterval = 0
    private var loadedAt: Date?
    private var revision = 0
    var serverNow: Date { Date().addingTimeInterval(clockOffset) }
    init(api: any DailyDuelsAPI) { self.api = api }
    func refresh(force: Bool = false) async {
        let expired = hub?.today.map { $0.closesAt <= serverNow } ?? false
        guard !busy, force || expired || loadedAt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        let requestRevision = revision
        busy = true; error = nil
        defer { busy = false }
        do {
            let incoming = try await api.dailyDuels()
            try Task.checkCancellation(); try incoming.validate()
            guard requestRevision == revision else { return }
            hub = incoming; clockOffset = incoming.serverTime.timeIntervalSinceNow; loadedAt = .now
        } catch is CancellationError {} catch { if requestRevision == revision { self.error = error.localizedDescription } }
    }
    func detail(id: String) async throws -> DailyDuelDetail {
        let value = try await api.dailyDuel(id: id)
        try Task.checkCancellation(); try value.validate(id: id)
        clockOffset = value.serverTime.timeIntervalSinceNow
        return value
    }
    func vote(id: String, choice: Int) async throws -> DailyDuelDetail {
        guard !voting, [0,1].contains(choice) else { throw SocialError.invalid }
        revision += 1
        voting = true
        defer { voting = false }
        let saved = try await api.voteDailyDuel(id: id, choice: choice)
        guard saved.saved, saved.id == id else { throw SocialError.invalid }
        let value = try await detail(id: id)
        loadedAt = nil // Revalidate the Home summary after returning from the arena.
        if let hub {
            self.hub = .init(serverTime: value.serverTime, today: hub.today?.id == id ? value.round : hub.today,
                             previous: hub.previous?.id == id ? value.round : hub.previous, progress: value.progress)
        }
        return value
    }
}
