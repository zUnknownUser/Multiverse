import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(ProStore.self) private var proStore
    @Environment(\.dismiss) private var dismiss
    @State private var settings = AccountSettings()
    @State private var blockedCount = 0
    @State private var showSignOutSheet = false

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 26) {
                Text(L10n.text("AJUSTES")).font(MVFont.display(30, width: 122)).foregroundStyle(MV.C.ink)

                proPromoRow
                accountSection
                themeSection
                privacySection
                notificationsSection
                creditsSection

                HStack(spacing: 10) {
                    Text(L10n.text("SAIR DA CONTA"))
                        .font(MVFont.bold(13))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .foregroundStyle(MV.C.ink)
                        .background(MV.C.card)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                        .contentShape(Rectangle())
                        .onTapGesture { showSignOutSheet = true }

                    Text(L10n.text("EXCLUIR CONTA"))
                        .font(MVFont.bold(13))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .foregroundStyle(MV.C.marvel)
                        .background(MV.C.card)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.marvel, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                        .contentShape(Rectangle())
                        .onTapGesture { store.push(.deleteAccount) }
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
        .task {
            settings = await auth.loadAccountSettings()
            if let social = store.social {
                await social.loadPrivacy()
                await social.loadBlocks()
            } else { blockedCount = await auth.loadBlockedUsers().count }
        }
        .onChange(of: settings) { _, newValue in Task { await auth.saveAccountSettings(newValue) } }
        .sheet(isPresented: $showSignOutSheet) { SignOutSheet() }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("CONTA")).kicker(11).foregroundStyle(MV.C.muted)
            VStack(spacing: 0) {
                infoRow(L10n.text("Usuário"), value: store.user(store.meID)?.handle ?? "")
                Divider().overlay(MV.C.divider)
                infoRow(L10n.text("E-mail"), value: maskedEmail)
                Divider().overlay(MV.C.divider)
                infoRow(L10n.text("Senha"), value: L10n.text("Alterar"))
            }
            .comicCard(shadow: MV.Shadow.s)
        }
    }

    private var proPromoRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(proStore.isPro ? L10n.text("VOCÊ É PRO") : "MULTIVERSE PRO").font(MVFont.black(14)).foregroundStyle(MV.C.paper)
                Text(proStore.isPro ? L10n.text("Seus números, temas e mais liberados.") : L10n.text("Estatísticas, temas e Wrapped anual."))
                    .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.paper.opacity(0.85))
            }
            Spacer()
            Text("→").font(MVFont.black(16)).foregroundStyle(MV.C.paper)
        }
        .padding(14)
        .background(MV.C.marvel)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .contentShape(Rectangle())
        .onTapGesture { store.push(proStore.isPro ? .proStats : .pro) }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("TEMA")).kicker(11).foregroundStyle(MV.C.muted)
            HStack(spacing: 0) {
                ForEach(ThemePreference.allCases, id: \.self) { option in
                    let selected = store.themePreference == option
                    Text(option.label.uppercased())
                        .font(MVFont.bold(12))
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .foregroundStyle(selected ? MV.C.paper : MV.C.ink)
                        .background(selected ? MV.C.ink : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { store.themePreference = option }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
            .comicCard(radius: MV.R.md, shadow: MV.Shadow.s)
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("PRIVACIDADE")).kicker(11).foregroundStyle(MV.C.muted)
            if let social = store.social, let error = social.privacyError {
                PeopleStatusNotice(message: error) { await social.loadPrivacy() }
            }
            VStack(spacing: 0) {
                toggleRow(L10n.text("Diário público"), note: L10n.text(store.social == nil ? "Qualquer pessoa vê o que você registra" : "Ao ativar, suas reviews anteriores e futuras ficam públicas para pessoas no app."), isOn: Binding(
                    get: { store.social?.publicDiary ?? (store.social == nil && settings.publicDiary) },
                    set: { value in
                        if let social = store.social { Task { _ = await social.setPublicDiary(value) } }
                        else { settings.publicDiary = value }
                    }))
                    .disabled(store.social.map { $0.publicDiary == nil || $0.isMutating } ?? false)
                Divider().overlay(MV.C.divider)
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("Quem pode comentar")).font(MVFont.bold(15)).foregroundStyle(MV.C.ink)
                    HStack(spacing: 0) {
                        ForEach(CommentPermission.allCases, id: \.self) { option in
                            let selected = (store.social == nil ? settings.whoCanComment : store.social?.commentPermission) == option
                            Text(L10n.text(option.rawValue).uppercased())
                                .font(MVFont.bold(11))
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .foregroundStyle(selected ? MV.C.paper : MV.C.ink)
                                .background(selected ? MV.C.ink : Color.clear)
                                .contentShape(Rectangle())
                                .allowsHitTesting(store.social.map { !$0.isMutating && $0.commentPermission != nil } ?? true)
                                .onTapGesture {
                                    if let social = store.social { Task { _ = await social.setCommentPermission(option) } }
                                    else { settings.whoCanComment = option }
                                }
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                }
                .padding(16)
                Divider().overlay(MV.C.divider)
                toggleRow(L10n.text("Esconder spoilers"), note: L10n.text("Borra reviews marcadas com spoiler"), isOn: Binding(get: { settings.hideSpoilers }, set: { settings.hideSpoilers = $0 }))
                Divider().overlay(MV.C.divider)
                infoRow(L10n.text("Usuários bloqueados"), value: "\(store.social?.blocks.count ?? blockedCount)") { store.push(.blockedUsers) }
            }
            .comicCard(shadow: MV.Shadow.s)
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("NOTIFICAÇÕES")).kicker(11).foregroundStyle(MV.C.muted)
            VStack(spacing: 0) {
                toggleRow(L10n.text("Curtidas e respostas"), isOn: Binding(get: { settings.likesAndReplies }, set: { settings.likesAndReplies = $0 }))
                Divider().overlay(MV.C.divider)
                toggleRow(L10n.text("Duelos e debates novos"), isOn: Binding(get: { settings.newDuelsAndDebates }, set: { settings.newDuelsAndDebates = $0 }))
            }
            .comicCard(shadow: MV.Shadow.s)
        }
    }

    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("CRÉDITOS")).kicker(11).foregroundStyle(MV.C.muted)
            VStack(alignment: .leading, spacing: 12) {
                Link(destination: URL(string: "https://www.themoviedb.org")!) {
                    Image("TMDBLogo")
                        .resizable().scaledToFit().frame(width: 110)
                        .accessibilityLabel(Text(verbatim: "TMDB"))
                }
                Text(L10n.text("Dados de filmes e séries fornecidos pelo TMDB."))
                    .font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.ink)
                // Official attribution notice, retained verbatim in both locales.
                Text(verbatim: "This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(MVFont.body(11)).foregroundStyle(MV.C.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(MV.C.divider)
                Link("Wikidata · CC0", destination: URL(string: "https://www.wikidata.org/wiki/Wikidata:Licensing")!)
                    .font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .comicCard(shadow: MV.Shadow.s)
        }
    }

    private func infoRow(_ label: String, value: String, action: (() -> Void)? = nil) -> some View {
        HStack {
            Text(label).font(MVFont.bold(15)).foregroundStyle(MV.C.ink)
            Spacer()
            Text(value + (action != nil ? " →" : "")).font(MVFont.body(14, weight: 600)).foregroundStyle(MV.C.muted)
        }
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }

    private func toggleRow(_ title: String, note: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(MVFont.bold(15)).foregroundStyle(MV.C.ink)
                if let note { Text(note).font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted) }
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(MV.C.wow)
        }
        .padding(16)
    }

    /// "duda.kaminski@gmail.com" → "duda.k...@gmail.com"
    private var maskedEmail: String {
        guard let email = auth.session?.email, let atIndex = email.firstIndex(of: "@") else { return "" }
        let localPart = email[..<atIndex].prefix(6)
        return "\(localPart)...\(email[atIndex...])"
    }
}

private struct SignOutSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(MV.C.ink).frame(width: 44, height: 5).frame(maxWidth: .infinity)
            Text(L10n.text("SAIR DA CONTA?")).font(MVFont.display(28, width: 118)).foregroundStyle(MV.C.ink)
            Text(L10n.format("Seu diário, reviews e votos continuam salvos. É só entrar de novo com %1$@.", String(describing: store.user(store.meID)?.handle ?? "")))
                .font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)

            Text(L10n.text("SAIR"))
                .font(MVFont.bold(15))
                .frame(maxWidth: .infinity).frame(height: 54)
                .foregroundStyle(MV.C.paper)
                .background(MV.C.ink)
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                .background(RoundedRectangle(cornerRadius: MV.R.md).fill(MV.C.marvel).offset(x: MV.Shadow.s, y: MV.Shadow.s))
                .contentShape(Rectangle())
                .onTapGesture { Task { await auth.signOut() } }

            Text(L10n.text("CANCELAR"))
                .font(MVFont.bold(15))
                .frame(maxWidth: .infinity).frame(height: 54)
                .foregroundStyle(MV.C.ink)
                .background(MV.C.card)
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
        }
        .padding(MV.pad)
        .padding(.bottom, 12)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.hidden)
    }
}
