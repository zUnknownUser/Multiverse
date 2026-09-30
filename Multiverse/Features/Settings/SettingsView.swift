import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var settings = AccountSettings()
    @State private var blockedCount = 0
    @State private var showSignOutSheet = false

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 26) {
                Text("AJUSTES").font(MVFont.display(30, width: 122)).foregroundStyle(MV.C.ink)

                accountSection
                privacySection
                notificationsSection

                HStack(spacing: 10) {
                    Text("SAIR DA CONTA")
                        .font(MVFont.bold(13))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .foregroundStyle(MV.C.ink)
                        .background(MV.C.card)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                        .contentShape(Rectangle())
                        .onTapGesture { showSignOutSheet = true }

                    Text("EXCLUIR CONTA")
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
            blockedCount = await auth.loadBlockedUsers().count
        }
        .onChange(of: settings) { _, newValue in Task { await auth.saveAccountSettings(newValue) } }
        .sheet(isPresented: $showSignOutSheet) { SignOutSheet() }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONTA").kicker(11).foregroundStyle(MV.C.muted)
            VStack(spacing: 0) {
                infoRow("Usuário", value: store.user(store.meID)?.handle ?? "")
                Divider().overlay(MV.C.divider)
                infoRow("E-mail", value: maskedEmail)
                Divider().overlay(MV.C.divider)
                infoRow("Senha", value: "Alterar")
            }
            .comicCard(shadow: MV.Shadow.s)
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRIVACIDADE").kicker(11).foregroundStyle(MV.C.muted)
            VStack(spacing: 0) {
                toggleRow("Diário público", note: "Qualquer pessoa vê o que você registra", isOn: Binding(get: { settings.publicDiary }, set: { settings.publicDiary = $0 }))
                Divider().overlay(MV.C.divider)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Quem pode comentar").font(MVFont.bold(15)).foregroundStyle(MV.C.ink)
                    HStack(spacing: 0) {
                        ForEach(CommentPermission.allCases, id: \.self) { option in
                            let selected = settings.whoCanComment == option
                            Text(option.rawValue.uppercased())
                                .font(MVFont.bold(11))
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .foregroundStyle(selected ? MV.C.paper : MV.C.ink)
                                .background(selected ? MV.C.ink : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { settings.whoCanComment = option }
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                }
                .padding(16)
                Divider().overlay(MV.C.divider)
                toggleRow("Esconder spoilers", note: "Borra reviews marcadas com spoiler", isOn: Binding(get: { settings.hideSpoilers }, set: { settings.hideSpoilers = $0 }))
                Divider().overlay(MV.C.divider)
                infoRow("Usuários bloqueados", value: "\(blockedCount)") { store.push(.blockedUsers) }
            }
            .comicCard(shadow: MV.Shadow.s)
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOTIFICAÇÕES").kicker(11).foregroundStyle(MV.C.muted)
            VStack(spacing: 0) {
                toggleRow("Curtidas e respostas", isOn: Binding(get: { settings.likesAndReplies }, set: { settings.likesAndReplies = $0 }))
                Divider().overlay(MV.C.divider)
                toggleRow("Duelos e debates novos", isOn: Binding(get: { settings.newDuelsAndDebates }, set: { settings.newDuelsAndDebates = $0 }))
            }
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
            Text("SAIR DA CONTA?").font(MVFont.display(28, width: 118)).foregroundStyle(MV.C.ink)
            Text("Seu diário, reviews e votos continuam salvos. É só entrar de novo com \(store.user(store.meID)?.handle ?? "").")
                .font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)

            Text("SAIR")
                .font(MVFont.bold(15))
                .frame(maxWidth: .infinity).frame(height: 54)
                .foregroundStyle(MV.C.paper)
                .background(MV.C.ink)
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                .background(RoundedRectangle(cornerRadius: MV.R.md).fill(MV.C.marvel).offset(x: MV.Shadow.s, y: MV.Shadow.s))
                .contentShape(Rectangle())
                .onTapGesture { Task { await auth.signOut() } }

            Text("CANCELAR")
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
