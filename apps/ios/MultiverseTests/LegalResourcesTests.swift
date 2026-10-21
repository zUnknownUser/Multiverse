import Foundation
import Testing
@testable import Multiverse

struct LegalResourcesTests {
    @Test func documentsAreBundledOfflineInBothLanguagesWithMatchingSections() throws {
        let portuguese = try LegalResources(preferredLanguages: ["pt-BR"])
        let english = try LegalResources(preferredLanguages: ["en"])
        for kind in LegalDocumentKind.allCases {
            let pt = portuguese.document(kind), en = english.document(kind)
            #expect(pt.title != en.title)
            #expect(pt.sections.map(\.id) == en.sections.map(\.id))
            #expect(zip(pt.sections, en.sections).allSatisfy { $0.body != $1.body })
        }
        #expect(try LegalResources(preferredLanguages: ["fr"]).document(.privacy).title == portuguese.document(.privacy).title)
    }

    @Test func missingContactCannotCreateADeadOrInventedEmailLink() throws {
        for email in [nil, "", "name@example.com?bcc=third@example.com", "Name <name@example.com>", "name@example.com\nBcc:x@example.com"] as [String?] {
            let configuration = LegalConfiguration(revision: "test", isDraft: true, responsibleName: nil, supportEmail: email)
            #expect(configuration.contactEmail == nil)
            #expect(configuration.emailURL(subject: "Ajuda", body: "Olá") == nil)
        }
    }

    @Test func emailDraftPreservesAccentsAndDelimitersWithoutAddingRecipients() throws {
        let configuration = LegalConfiguration(revision: "test", isDraft: false, responsibleName: "Test", supportEmail: "help+privacy@example.com")
        let url = try #require(configuration.emailURL(subject: "Privacidade & suporte?", body: "Olá\nVersão: 1.0 & assunto=teste"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "mailto")
        #expect(components.path == "help+privacy@example.com")
        #expect(components.queryItems == [URLQueryItem(name: "subject", value: "Privacidade & suporte?"), URLQueryItem(name: "body", value: "Olá\nVersão: 1.0 & assunto=teste")])
    }

    @Test func privacyManifestsAreEmbeddedInAppAndWidget() throws {
        func manifest(_ url: URL) throws -> [String: Any] {
            try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        }
        let appURL = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let app = try manifest(appURL)
        let extensions = try #require(Bundle.main.builtInPlugInsURL)
        let widget = try manifest(extensions.appendingPathComponent("MultiverseWidgets.appex/PrivacyInfo.xcprivacy"))
        for value in [app, widget] {
            #expect(value["NSPrivacyTracking"] as? Bool == false)
            let accessed = try #require(value["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
            #expect(accessed.first?["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
            #expect((accessed.first?["NSPrivacyAccessedAPITypeReasons"] as? [String])?.contains("1C8F.1") == true)
        }
        #expect(Bundle.main.object(forInfoDictionaryKey: "FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED") as? Bool == true)
    }
}
