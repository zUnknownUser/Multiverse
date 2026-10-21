import Foundation
import Testing
@testable import Multiverse

@Suite("Deployment isolation")
struct AppEnvironmentTests {
    @Test func stagingRejectsProductionAndUnsafeURLs() {
        for value in ["https://api-production-6e8d.up.railway.app/api/v1", "https://API-PRODUCTION-6E8D.UP.RAILWAY.APP/api/v1",
                      "http://example.com/api/v1", "https://user@example.com/api/v1", "https://example.com/api/v1?env=production",
                      "https://example.com/api/v1#fragment", "", "$(MULTIVERSE_API_BASE_URL)"] {
            #expect(AppEnvironment.staging.apiURL(value) == nil)
        }
        #expect(AppEnvironment.staging.apiURL("https://staging.example.invalid/api/v1") != nil)
        #if DEBUG
        #expect(AppEnvironment.staging.apiURL("http://127.0.0.1:3000/api/v1") != nil)
        #endif
    }
    @Test func productionRejectsLocalAndOtherHosts() {
        #expect(AppEnvironment.production.apiURL("https://api-production-6e8d.up.railway.app/api/v1") != nil)
        #expect(AppEnvironment.production.apiURL("http://localhost:3000/api/v1") == nil)
        #expect(AppEnvironment.production.apiURL("https://staging.example.invalid/api/v1") == nil)
    }
    @Test func buildHasDistinctAppWidgetsAndFirebaseIdentity() throws {
        #expect(AppEnvironment.current.bundleID == Bundle.main.bundleIdentifier)
        #expect(AppEnvironment.staging.appGroupID != AppEnvironment.production.appGroupID)
        #expect(WidgetBridge.appGroupID == AppEnvironment.current.appGroupID)
        let url = try #require(Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"))
        let firebase = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(firebase["PROJECT_ID"] as? String == AppEnvironment.current.firebaseProjectID)
        let extensions = Bundle.main.builtInPlugInsURL!
        let widget = try #require(Bundle(url: extensions.appendingPathComponent("MultiverseWidgets.appex")))
        #expect(widget.bundleIdentifier == AppEnvironment.current.bundleID + ".widgets")
        #expect(widget.object(forInfoDictionaryKey: "MultiverseEnvironment") as? String == AppEnvironment.current.rawValue)
    }
    @Test func invitationsCannotCrossEnvironments() throws {
        let id = UUID().uuidString.lowercased()
        let other: AppEnvironment = AppEnvironment.current == .production ? .staging : .production
        #expect(DuelInvitation.id(in: other.urlScheme + "://duel/" + id) == nil)
        #expect(DuelInvitation.id(in: try #require(DuelInvitation.url(id: id)).absoluteString) == id)
    }
}
