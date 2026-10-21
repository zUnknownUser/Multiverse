import Foundation

/// Deployment identity is shared by the app, HTTP clients, links and widgets.
enum AppEnvironment: String, Sendable {
    case staging, production

    static var current: Self {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MultiverseEnvironment") as? String,
              let environment = Self(rawValue: value) else { preconditionFailure("Missing deployment configuration") }
        return environment
    }
    var firebaseProjectID: String { self == .production ? "multiverse-7f87c" : "multiverse-staging-7f87c" }
    var bundleID: String { self == .production ? "com.nexussoft.multiverse" : "com.nexussoft.multiverse.staging" }
    var appGroupID: String { "group." + bundleID }
    var urlScheme: String { self == .production ? "multiverse" : "multiverse-staging" }

    func apiURL(_ value: String) -> URL? {
        guard let url = URL(string: value), let host = url.host?.lowercased(), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        let productionHost = "api-production-6e8d.up.railway.app"
        if self == .production {
            guard url.scheme == "https", host == productionHost, url.port == nil || url.port == 443 else { return nil }
        } else {
            guard host != productionHost else { return nil }
            #if DEBUG
            guard url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)) else { return nil }
            #else
            guard url.scheme == "https" else { return nil }
            #endif
        }
        guard url.path == "/api/v1" || url.path == "/api/v1/" else { return nil }
        return url
    }
}
