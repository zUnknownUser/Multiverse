import SwiftUI

struct DuelNominationControl: View {
    let post: CommunityPost
    @Environment(AppStore.self) private var store
    @State private var candidate: DuelCandidate?
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirming = false
    @State private var withdrawing = false
    private var eligible: Bool { !post.spoiler && post.clubID == nil && (post.segment ?? 0) == 0 }
    var body: some View {
        if store.duelCurationAPI != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let candidate {
                    DuelCandidateStatus(candidate: candidate)
                    if candidate.canWithdraw { Button(L10n.text("RETIRAR SUGESTÃO")) { withdrawing = true } }
                } else if loaded && eligible {
                    Button { confirming = true } label: {
                        Label(L10n.text("SUGERIR PARA O DUELO DO DIA"), systemImage: "sparkles")
                    }
                } else if loaded {
                    Text(L10n.text("Para sugerir, publique um duelo sem spoilers e fora de clubes.")).font(MVFont.body(12)).foregroundStyle(MV.C.muted)
                }
                if busy { ProgressView() }
                if let error { PeopleStatusNotice(message: error) { await run(.load) } }
            }.font(MVFont.bold(12)).disabled(busy)
            .task(id: post.version) { await run(.load) }
            .confirmationDialog(L10n.text("Sugerir este duelo?"), isPresented: $confirming, titleVisibility: .visible) {
                Button(L10n.text("ENVIAR PARA REVISÃO")) { Task { await run(.submit) } }
            } message: {
                Text(L10n.text("A equipe revisará e adaptará sua ideia em português e inglês. Se escolhida, ela ganhará uma nova rodada com crédito no seu perfil público. Os votos deste post ficam aqui. Até 3 sugestões ativas e 3 envios por dia."))
            }
            .confirmationDialog(L10n.text("Retirar esta sugestão da fila?"), isPresented: $withdrawing, titleVisibility: .visible) {
                Button(L10n.text("RETIRAR SUGESTÃO"), role: .destructive) { Task { await run(.withdraw) } }
            }
        }
    }
    private enum Action: Equatable { case load, submit, withdraw }
    private func run(_ action: Action) async {
        guard !busy, let api = store.duelCurationAPI else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let receipt: DuelCandidateReceipt
            switch action {
            case .load: receipt = try await api.duelCandidate(post: post.id)
            case .submit: receipt = try await api.suggestDuel(post: post.id)
            case .withdraw: receipt = try await api.withdrawDuel(post: post.id)
            }
            try Task.checkCancellation()
            try receipt.candidate?.validate()
            if action != .load && receipt.candidate == nil { throw SocialError.invalid }
            guard receipt.candidate == nil || receipt.candidate?.postID == post.id else { throw SocialError.invalid }
            candidate = receipt.candidate; loaded = true
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
struct DuelCandidateStatus: View {
    let candidate: DuelCandidate
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(candidate.statusLabel, systemImage: candidate.status == "published" ? "checkmark.seal" : "sparkles").kicker(11)
            if let day = candidate.scheduledOn, candidate.status == "approved" {
                Text(L10n.format("Rodada de %@ (UTC)", day)).font(MVFont.body(12)).foregroundStyle(MV.C.muted)
            }
            if let explanation = candidate.explanation { Text(explanation).font(MVFont.body(12)).foregroundStyle(MV.C.muted) }
        }
    }
}
struct DuelSuggestionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var items: [DuelCandidate] = []
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var creating = false
    @State private var selected: DuelCandidate?
    var body: some View {
        NavigationStack {
            ScreenScaffold(showBack: true, onBack: { dismiss() }) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text("MINHAS SUGESTÕES")).font(MVFont.display(26, width: 118))
                    Text(L10n.text("Sua ideia pode virar o Duelo do Dia. Crie um duelo na comunidade e, na publicação, toque em sugerir. A seleção passa por revisão em português e inglês."))
                        .font(MVFont.body(13)).foregroundStyle(MV.C.muted)
                    Button { creating = true } label: {
                        Label(L10n.text("CRIAR MEU DUELO NA COMUNIDADE"), systemImage: "square.and.pencil").font(MVFont.bold(12))
                    }.buttonStyle(.plain)
                    if busy { ProgressView() }
                    if let error { PeopleStatusNotice(message: error) { await load() } }
                    if loaded && items.isEmpty { LibraryEmptyState(message: L10n.text("A próxima conversa pode começar com você. Suas sugestões aparecerão aqui.")) }
                    ForEach(items) { candidate in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(candidate.title).font(MVFont.bold(16)).fixedSize(horizontal: false, vertical: true)
                            DuelCandidateStatus(candidate: candidate)
                            if let published = candidate.publishedPostID {
                                Button(L10n.text("VER NA ARENA")) { dismiss(); store.push(.dailyDuel(published)) }
                            } else if let post = candidate.postID {
                                Button(L10n.text("VER PUBLICAÇÃO")) { dismiss(); store.push(.post(post)) }
                            }
                            if candidate.canWithdraw { Button(L10n.text("RETIRAR SUGESTÃO")) { selected = candidate } }
                        }.font(MVFont.bold(12)).padding(14).comicCard()
                    }
                    if items.count == 100 { Text(L10n.text("Mostrando as 100 sugestões mais recentes.")).font(MVFont.body(12)).foregroundStyle(MV.C.muted) }
                }.padding(MV.pad).foregroundStyle(MV.C.ink)
            }.task { await load() }.refreshable { await load() }
            .sheet(isPresented: $creating, onDismiss: { dismiss() }) { PostComposer(universe: nil, item: nil, kind: "duel") }
            .confirmationDialog(L10n.text("Retirar esta sugestão da fila?"), isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
                if let candidate = selected {
                    Button(L10n.text("RETIRAR SUGESTÃO"), role: .destructive) { Task { await withdraw(candidate) } }
                }
            }
        }
    }
    private func load() async {
        guard !busy, let api = store.duelCurationAPI else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let page = try await api.myDuelCandidates()
            try Task.checkCancellation()
            guard page.items.count <= 100, Set(page.items.map(\.id)).count == page.items.count else { throw SocialError.invalid }
            try page.items.forEach { try $0.validate() }
            items = page.items; loaded = true
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func withdraw(_ candidate: DuelCandidate) async {
        guard !busy, let api = store.duelCurationAPI, let post = candidate.postID else { return }
        busy = true; error = nil
        do {
            _ = try await api.withdrawDuel(post: post)
            busy = false; await load()
        } catch { busy = false; self.error = error.localizedDescription }
    }
}
