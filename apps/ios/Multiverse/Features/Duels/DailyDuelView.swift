import SwiftUI

struct DailyDuelView: View {
    let id: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var detail: DailyDuelDetail?
    @State private var error: String?
    @State private var loading = false
    @State private var ranking = false
    @State private var inviting = false
    @State private var debate = false
    @State private var reward = false
    @State private var creating = false
    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text(L10n.text("DUELO DO DIA")).font(MVFont.display(28, width: 118)); Spacer(); Image(systemName: "bolt.fill").foregroundStyle(MV.C.marvel) }
                if let error { PeopleStatusNotice(message: error) { await load() } }
                if loading && detail == nil { ProgressView().frame(maxWidth: .infinity) }
                if let detail, let duels = store.dailyDuels {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        roundContent(detail.round, duels: duels)
                    }
                    progress(detail.progress)
                    Button { ranking = true } label: {
                        HStack { Label(L10n.text("RANKING DO MÊS"), systemImage: "trophy"); Spacer(); Image(systemName: "arrow.up.right") }
                            .font(MVFont.bold(13)).foregroundStyle(MV.C.ink).padding(16).comicCard()
                    }.buttonStyle(.plain)
                    Text(L10n.text("Cada rodada vale 10 pontos, uma única vez. Ao votar, você participa do ranking público mensal. Comentários, convites e troca de lado não dão pontos extras."))
                        .font(MVFont.body(12)).foregroundStyle(MV.C.muted)
                    Button { creating = true } label: {
                        Label(L10n.text("CRIAR MEU DUELO NA COMUNIDADE"), systemImage: "square.and.pencil")
                            .font(MVFont.bold(12)).foregroundStyle(MV.C.ink)
                    }.buttonStyle(.plain)
                }
            }.padding(MV.pad).foregroundStyle(MV.C.ink)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await load()
            if let detail, let duels = store.dailyDuels {
                let remaining = detail.round.closesAt.timeIntervalSince(duels.serverNow)
                if remaining > 0 {
                    do { try await Task.sleep(for: .seconds(remaining + 1)) } catch { return }
                    await load()
                }
            }
        }
        .sensoryFeedback(.success, trigger: reward)
        .refreshable { await load() }
        .sheet(isPresented: $creating) {
            PostComposer(universe: detail?.round.universeID, item: nil, kind: "duel")
        }
        .sheet(isPresented: $ranking) { DuelLeaderboardView() }
        .sheet(isPresented: $inviting) { if let round = detail?.round { DuelInviteView(round: round) } }
        .sheet(isPresented: $debate, onDismiss: { Task { await load() } }) { NavigationStack { PostView(id: id) } }
    }
    private func roundContent(_ round: DailyDuelRound, duels: DailyDuelsStore) -> some View {
        let closed = round.closesAt <= duels.serverNow
        return VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("CURADORIA MULTIVERSE")).kicker(10).foregroundStyle(MV.C.muted)
            Text(round.title).font(MVFont.black(23)).fixedSize(horizontal: false, vertical: true)
            Text(closed ? L10n.text("Votação encerrada") : L10n.format("Encerra em %@ min", String(max(1, Int(ceil(round.closesAt.timeIntervalSince(duels.serverNow) / 60))))))
                .font(MVFont.bold(12)).foregroundStyle(MV.C.muted)
            if !closed && round.votes.mine == nil {
                Text(L10n.text("Seu primeiro voto nesta rodada vale 10 pontos e inclui seu perfil no ranking mensal."))
                    .font(MVFont.body(12)).foregroundStyle(MV.C.muted)
            }
            ForEach(0..<2, id: \.self) { choice in
                if closed {
                    optionLabel(round, choice: choice, showResults: true)
                } else {
                    Button { Task { await vote(choice) } } label: {
                        optionLabel(round, choice: choice, showResults: round.votes.mine != nil)
                    }.buttonStyle(.plain).disabled(loading || duels.voting)
                }
            }
            if duels.voting { ProgressView() }
            if closed {
                Text(result(round)).font(MVFont.bold(14)).foregroundStyle(MV.C.dc)
            } else if reward {
                Label(L10n.text("PRESENÇA CONFIRMADA · +10 PONTOS"), systemImage: "sparkles").font(MVFont.bold(12)).foregroundStyle(MV.C.dc)
            }
            Text(L10n.format("%1$@ votos · %2$@ comentários", String(round.totalVotes), String(round.commentCount)))
                .font(MVFont.body(12)).foregroundStyle(MV.C.muted)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { actions }
                VStack(alignment: .leading, spacing: 16) { actions }
            }
        }
    }
    private func optionLabel(_ round: DailyDuelRound, choice: Int, showResults: Bool) -> some View {
        let chosen = round.votes.mine == choice
        return HStack(spacing: 12) {
            Text(choice == 0 ? round.optionA : round.optionB).font(MVFont.bold(17)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if chosen { Image(systemName: "checkmark.circle.fill") }
            if showResults {
                Text(round.totalVotes == 0 ? "—" : "\(Int((Double(round.votes.counts[choice]) / Double(round.totalVotes) * 100).rounded()))%")
                    .font(MVFont.black(22)).monospacedDigit()
            }
        }.foregroundStyle(MV.C.ink).padding(18)
            .background(chosen ? (choice == 0 ? MV.C.marvel : MV.C.dc).opacity(0.16) : Color.clear)
            .comicCard(bg: MV.C.card, shadow: chosen ? MV.Shadow.s : 0)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
    private var actions: some View {
        Group {
            Button { debate = true } label: { Label(L10n.text("DEFENDER MEU LADO"), systemImage: "bubble.left.and.bubble.right") }
            Button { inviting = true } label: { Label(L10n.text("CHAMAR UM AMIGO"), systemImage: "person.badge.plus") }
        }.font(MVFont.bold(11)).foregroundStyle(MV.C.ink).buttonStyle(.plain)
    }
    private func progress(_ value: DuelProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(value.title, systemImage: "seal.fill").font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
            Text(L10n.format("%1$@ pontos no mês · sequência de %2$@ dias", String(value.monthlyPoints), String(value.streak)))
                .font(MVFont.body(12)).fixedSize(horizontal: false, vertical: true)
            if let next = value.nextMilestone {
                ProgressView(value: Double(value.rounds), total: Double(next)).tint(MV.C.dc)
                Text(L10n.format("%1$@ de %2$@ rodadas para o próximo título", String(value.rounds), String(next))).font(MVFont.body(12)).foregroundStyle(MV.C.muted)
            }
            Text(L10n.text("Seus títulos ficam. O ranking recomeça a cada mês."))
                .font(MVFont.body(11)).foregroundStyle(MV.C.muted)
        }.padding(16).comicCard(shadow: 0)
    }
    private func result(_ round: DailyDuelRound) -> String {
        if round.totalVotes == 0 { return L10n.text("Esta rodada terminou sem votos.") }
        if round.votes.counts[0] == round.votes.counts[1] { return L10n.text("EMPATE NA ARENA") }
        return L10n.format("ESCOLHA DA COMUNIDADE: %@", round.votes.counts[0] > round.votes.counts[1] ? round.optionA : round.optionB)
    }
    private func load() async {
        guard !loading, let duels = store.dailyDuels, !duels.voting else { return }
        loading = true; error = nil
        defer { loading = false }
        do { detail = try await duels.detail(id: id) }
        catch is CancellationError {} catch { self.error = error.localizedDescription; if error is CommunityError { detail = nil } }
    }
    private func vote(_ choice: Int) async {
        guard !loading, let duels = store.dailyDuels, !duels.voting else { return }
        let previousRounds = detail?.progress.rounds ?? 0
        error = nil
        do { detail = try await duels.vote(id: id, choice: choice); reward = (detail?.progress.rounds ?? 0) > previousRounds }
        catch { self.error = error.localizedDescription }
    }
}
