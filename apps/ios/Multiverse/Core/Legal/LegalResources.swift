import Foundation

enum LegalDocumentKind: String, CaseIterable, Codable, Hashable {
    case terms, privacy, support

    var title: String {
        switch self {
        case .terms: L10n.text("Termos de Uso")
        case .privacy: L10n.text("Política de Privacidade")
        case .support: L10n.text("Ajuda e suporte")
        }
    }
}

struct LegalDocument: Decodable {
    struct Section: Decodable, Identifiable {
        let id: String
        let title: String
        let body: String
    }
    let title: String
    let sections: [Section]
}

struct LegalConfiguration: Decodable {
    let revision: String
    let isDraft: Bool
    let responsibleName: String?
    let supportEmail: String?

    var contactEmail: String? {
        guard let email = supportEmail, email.range(of: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil else { return nil }
        return email
    }

    func emailURL(subject: String, body: String) -> URL? {
        guard let email = contactEmail else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return components.url
    }
}

/// Offline documents share the same localized resources used for public-page export.
/// No account or network dependency: available before authentication and in Settings.
struct LegalResources {
    let configuration: LegalConfiguration
    private let documents: [String: LegalDocument]

    init(bundle: Bundle = .main, preferredLanguages: [String] = Locale.preferredLanguages) throws {
        guard let configURL = bundle.url(forResource: "LegalConfiguration", withExtension: "json"),
              let documentsURL = L10n.resourceURL(named: "LegalDocuments", extension: "json", preferredLanguages: preferredLanguages, bundle: bundle) else {
            throw CocoaError(.fileNoSuchFile)
        }
        configuration = try JSONDecoder().decode(LegalConfiguration.self, from: Data(contentsOf: configURL))
        documents = try JSONDecoder().decode([String: LegalDocument].self, from: Data(contentsOf: documentsURL))
        for kind in LegalDocumentKind.allCases {
            guard let document = documents[kind.rawValue], !document.title.isEmpty, !document.sections.isEmpty,
                  Set(document.sections.map(\.id)).count == document.sections.count,
                  document.sections.allSatisfy({ !$0.title.isEmpty && !$0.body.isEmpty }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }

    func document(_ kind: LegalDocumentKind) -> LegalDocument { documents[kind.rawValue]! }
}
