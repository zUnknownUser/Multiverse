import SwiftUI

struct LegalDocumentView: View {
    let kind: LegalDocumentKind
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var resources: LegalResources?
    @State private var loadFailed = false
    @State private var contactMessage: String?

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 22) {
                Text(kind.title.uppercased())
                    .font(MVFont.display(28, width: 115)).foregroundStyle(MV.C.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let resources {
                    Text(L10n.format("Versão: %@", resources.configuration.revision))
                        .font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.muted)
                    if resources.configuration.isDraft {
                        Text(L10n.text("Documento em revisão antes do lançamento público."))
                            .font(MVFont.body(13, weight: 600)).foregroundStyle(MV.C.ink)
                            .padding(14).comicCard(shadow: MV.Shadow.s)
                    }
                    if let name = resources.configuration.responsibleName {
                        Text(L10n.format("Responsável: %@", name)).font(MVFont.body(14, weight: 600)).foregroundStyle(MV.C.ink)
                    }
                    ForEach(resources.document(kind).sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title).font(MVFont.bold(17)).accessibilityAddTraits(.isHeader)
                            Text(section.body).font(MVFont.body(15)).textSelection(.enabled)
                        }
                        .foregroundStyle(MV.C.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    contact(resources.configuration)
                } else if loadFailed {
                    AuthErrorBanner(message: L10n.text("Não foi possível abrir este documento."))
                    Button(L10n.text("TENTAR DE NOVO"), action: load).font(MVFont.bold(14))
                } else { ProgressView() }
            }
            .padding(.horizontal, MV.pad).padding(.bottom, 28)
        }
        .task { load() }
    }

    @ViewBuilder private func contact(_ configuration: LegalConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("FALE COM A GENTE")).kicker(12).foregroundStyle(MV.C.muted)
            if let email = configuration.contactEmail {
                Text(email).font(MVFont.body(14, weight: 600)).foregroundStyle(MV.C.ink).textSelection(.enabled)
                Text(L10n.text("Descreva o problema. Não envie senha, código de verificação ou dados de outras pessoas."))
                    .font(MVFont.body(13)).foregroundStyle(MV.C.muted)
                Button {
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                    let body = L10n.format("Versão do app: %@\n\nDescreva sua solicitação:\n", version)
                    if let url = configuration.emailURL(subject: "Multiverse · \(kind.title)", body: body) {
                        openURL(url) { accepted in
                            if !accepted { contactMessage = L10n.text("Não foi possível abrir seu app de e-mail. Copie o endereço para entrar em contato.") }
                        }
                    }
                } label: {
                    Text(L10n.text("ESCREVER E-MAIL")).font(MVFont.bold(14))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button {
                    UIPasteboard.general.string = email
                    contactMessage = L10n.text("E-mail copiado.")
                } label: {
                    Text(L10n.text("COPIAR E-MAIL")).font(MVFont.bold(13))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if let contactMessage {
                    Text(contactMessage).font(MVFont.body(13)).foregroundStyle(MV.C.muted)
                }
            } else {
                Text(L10n.text("O canal de atendimento será informado antes do lançamento público."))
                    .font(MVFont.body(14)).foregroundStyle(MV.C.muted)
            }
        }
        .foregroundStyle(MV.C.ink)
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).comicCard(shadow: MV.Shadow.s)
    }

    private func load() {
        do { resources = try LegalResources(); loadFailed = false }
        catch { loadFailed = true }
    }
}
