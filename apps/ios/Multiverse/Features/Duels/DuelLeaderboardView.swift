import SwiftUI

struct DuelLeaderboardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var ranking: DuelLeaderboard?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        NavigationStack {
            ScreenScaffold(showBack: true, onBack: { dismiss() }) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text("RANKING DO MÊS")).font(MVFont.display(26, width: 118))
                    Text(L10n.text("Presença vale mais que popularidade. Empates compartilham a mesma posição."))
                        .font(MVFont.body(13)).foregroundStyle(MV.C.muted)
                    if loading { ProgressView() }
                    if let error { PeopleStatusNotice(message: error) { await load() } }
                    if let ranking {
                        Text(monthLabel(ranking.month)).kicker(12)
                        if let me = ranking.me { row(me, me: true) }
                        if ranking.leaders.isEmpty {
                            LibraryEmptyState(message: L10n.text("A arena está começando. Participe da rodada de hoje para entrar no ranking."))
                        }
                        ForEach(ranking.leaders) { entry in
                            Button { dismiss(); store.openUserProfile(entry.id) } label: { row(entry, me: false) }.buttonStyle(.plain)
                        }
                        Text(L10n.text("Até 30 participantes em destaque. Sua posição aparece mesmo fora da lista."))
                            .font(MVFont.body(11)).foregroundStyle(MV.C.muted)
                    }
                }.padding(MV.pad)
            }.task { await load() }.refreshable { await load() }
        }
    }
    private func monthLabel(_ month: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: month + "-15T12:00:00Z") else { return month }
        return L10n.date(date, template: "MMMM yyyy")
    }
    private func row(_ entry: DuelLeader, me: Bool) -> some View {
        HStack(spacing: 12) {
            Text("#\(entry.rank)").font(MVFont.black(23)).foregroundStyle(MV.C.dc)
            VStack(alignment: .leading, spacing: 4) {
                Text(me ? L10n.text("SUA POSIÇÃO") : entry.name).font(MVFont.bold(14)).lineLimit(2)
                Text(entry.handle).font(MVFont.body(11)).foregroundStyle(MV.C.muted).lineLimit(1)
            }
            Spacer()
            Text(L10n.format("%@ pontos", String(entry.points))).font(MVFont.bold(12))
        }.foregroundStyle(MV.C.ink).padding(14).comicCard(bg: me ? MV.C.dc.opacity(0.12) : MV.C.card, shadow: 0)
    }
    private func load() async {
        guard !loading, let duels = store.dailyDuels else { return }
        loading = true; error = nil
        defer { loading = false }
        do { let value = try await duels.api.duelLeaderboard(); try Task.checkCancellation(); try value.validate(owner: store.meID); ranking = value }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct DuelInviteView: View {
    let round: DailyDuelRound
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var recipient: String?
    @State private var recipientName: String?
    @State private var messageID = UUID().uuidString.lowercased()
    @State private var sending = false
    @State private var attempted = false
    @State private var error: String?
    private var message: String { L10n.format("Qual é o seu lado? %@", round.title) + "\n" + (DuelInvitation.url(id: round.id)?.absoluteString ?? "") }
    var body: some View {
        NavigationStack {
            ScreenScaffold(showBack: true, onBack: { dismiss() }) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L10n.text("CHAMAR UM AMIGO")).font(MVFont.display(25, width: 118))
                    Text(round.title).font(MVFont.bold(18))
                    Text(L10n.text("O convite chega por mensagem privada. Quem não segue você recebe um pedido de conversa."))
                        .font(MVFont.body(13)).foregroundStyle(MV.C.muted)
                    if let error { AuthErrorBanner(message: error) }
                    Button { choosing = true } label: {
                        Label(recipient.map { recipientName ?? store.user($0)?.handle ?? L10n.text("PESSOA SELECIONADA") } ?? L10n.text("ESCOLHER PESSOA"), systemImage: "person.crop.circle.badge.plus")
                            .font(MVFont.bold(14)).foregroundStyle(MV.C.ink).padding(16).frame(maxWidth: .infinity).comicCard()
                    }.buttonStyle(.plain).disabled(sending || attempted)
                    PrimaryAuthButton(title: L10n.text(attempted ? "REENVIAR" : "ENVIAR CONVITE"), enabled: recipient != nil && !sending) {
                        Task { await send() }
                    }
                    if sending { ProgressView().frame(maxWidth: .infinity) }
                }.padding(MV.pad)
            }
            .sheet(isPresented: $choosing) {
                DirectPeoplePicker(api: store.peopleAPI, owner: store.meID, onPick: { recipient = $0 }, onPickUser: { recipientName = $0.handle })
            }
        }.interactiveDismissDisabled(sending)
    }
    private func send() async {
        guard !sending, let recipient, let api = store.directMessages?.api else { return }
        sending = true; attempted = true; error = nil
        defer { sending = false }
        do {
            let result = try await api.sendDirect(peer: recipient, id: messageID, input: .init(kind: "text", text: message, itemID: nil, spoiler: false))
            guard result.saved, result.id == messageID else { throw SocialError.invalid }
            store.showToast(L10n.text("CONVITE ENVIADO")); dismiss()
            await store.directMessages?.refresh()
        } catch { self.error = error.localizedDescription }
    }
}
