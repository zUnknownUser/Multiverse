import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Ponte de dados entre o app e a extensão de widgets (`MultiverseWidgets/`), via App Group.
/// Este arquivo é compilado nos dois targets (ver `project.yml`) — é a única coisa que os
/// widgets sabem sobre o app.
///
/// **Setup no Xcode (não dá pra fazer sem Team ID real):** Signing & Capabilities → "+ Capability"
/// → App Groups → crie/marque o mesmo grupo nos targets `Multiverse` e `MultiverseWidgets`,
/// e troque `appGroupID` abaixo pelo identificador real gerado (geralmente
/// `group.<bundle-id-do-app>`).
enum WidgetBridge {
    static let appGroupID = "group.com.multiverse.app"
    private static let key = "widget-snapshot"

    struct Snapshot: Codable {
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

    static func save(_ snapshot: Snapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID), let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func load() -> Snapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID), let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}
