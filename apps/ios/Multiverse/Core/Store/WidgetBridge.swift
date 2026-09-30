import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
protocol WidgetSnapshotWriting {
    func save(_ snapshot: WidgetBridge.Snapshot)
}

/// Contrato compartilhado pelo app e pelos widgets através do App Group.
enum WidgetBridge {
    static let appGroupID = "group.com.nexussoft.multiverse"
    private static let key = "widget-snapshot"

    struct Snapshot: Codable, Equatable, Sendable {
        var universeName: String
        var universePercent: Int
        var universePercentDelta: Int
        var nextOrderItemTitle: String
        var nextOrderDone: Int
        var nextOrderTotal: Int
        var duelQuestion: String
        var duelSideATitle: String
        var duelSideBTitle: String
        var duelVotesLabel: String
    }

    private struct Envelope: Codable {
        let sessionID: UUID
        var snapshot: Snapshot?
    }

    /// Cada sessão recebe um escritor próprio. Carregamentos de stores anteriores
    /// não podem repor os dados após logout ou troca de conta, mesmo se ignorarem cancelamento.
    @MainActor
    final class Session: WidgetSnapshotWriting {
        private let id: UUID
        private let defaults: UserDefaults
        private let reload: @MainActor () -> Void

        fileprivate init(id: UUID, defaults: UserDefaults, reload: @escaping @MainActor () -> Void) {
            self.id = id
            self.defaults = defaults
            self.reload = reload
        }

        func save(_ snapshot: Snapshot) {
            guard envelope(in: defaults)?.sessionID == id,
                  let data = try? JSONEncoder().encode(Envelope(sessionID: id, snapshot: snapshot)) else { return }
            defaults.set(data, forKey: key)
            reload()
        }
    }

    @MainActor
    static func beginSession(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID),
        reload: @escaping @MainActor () -> Void = reloadTimelines
    ) -> Session? {
        guard let defaults else { return nil }
        let id = UUID()
        guard let data = try? JSONEncoder().encode(Envelope(sessionID: id, snapshot: nil)) else { return nil }
        // Identidade e conteúdo mudam juntos; nunca expomos o snapshot da sessão anterior.
        defaults.set(data, forKey: key)
        reload()
        return Session(id: id, defaults: defaults, reload: reload)
    }

    @MainActor
    static func clear(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID),
        reload: @escaping @MainActor () -> Void = reloadTimelines
    ) {
        defaults?.removeObject(forKey: key)
        reload()
    }

    static func load(defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)) -> Snapshot? {
        guard let defaults else { return nil }
        return envelope(in: defaults)?.snapshot
    }

    private static func envelope(in defaults: UserDefaults) -> Envelope? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Envelope.self, from: data)
    }

    @MainActor
    static func reloadTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
