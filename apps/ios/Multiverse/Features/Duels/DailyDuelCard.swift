import SwiftUI

/// Live replacement for the original Home duel card, using the same comic styling.
struct DailyDuelCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var suggestions = false
    var body: some View {
        if let duels = store.dailyDuels {
            VStack(alignment: .leading, spacing: 12) {
                if let round = duels.hub?.today {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(L10n.text("DUELO DO DIA")).kicker(11)
                            Spacer()
                            Image(systemName: "bolt.fill")
                        }.foregroundStyle(MV.C.card).padding(12).background(MV.C.ink)
                        VStack(alignment: .leading, spacing: 14) {
                            Text(round.title).font(MVFont.black(19)).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 10) {
                                side(round.optionA, color: MV.C.marvel)
                                Text("VS").font(MVFont.black(15))
                                side(round.optionB, color: MV.C.dc)
                            }
                            Text(round.votes.mine == nil ? L10n.text("Seu lado. Seu argumento. Sua arena.") : L10n.text("Você já marcou presença. O debate continua."))
                                .font(MVFont.body(12)).foregroundStyle(MV.C.muted)
                            Button { store.push(.dailyDuel(round.id)) } label: {
                                HStack {
                                    Text(round.votes.mine == nil ? L10n.text("ESCOLHER MEU LADO") : L10n.text("VOLTAR À ARENA"))
                                    Spacer(); Image(systemName: "arrow.up.right")
                                }.font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                            }.buttonStyle(.plain)
                        }.padding(.horizontal, 14).padding(.bottom, 14)
                    }.foregroundStyle(MV.C.ink).comicCard(shadow: MV.Shadow.m)
                    if let previous = duels.hub?.previous {
                        Button { store.push(.dailyDuel(previous.id)) } label: {
                            Label(L10n.text("VER RESULTADO ANTERIOR"), systemImage: "flag.checkered")
                                .font(MVFont.bold(11)).foregroundStyle(MV.C.muted)
                        }.buttonStyle(.plain)
                    }
                } else if duels.busy { ProgressView().frame(maxWidth: .infinity) }
                else if duels.hub != nil && duels.error == nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.text("DUELO DO DIA")).kicker(11)
                        Text(L10n.text("A próxima rodada está em preparação. Enquanto isso, sua ideia pode abrir um novo debate.")).font(MVFont.body(13))
                        if let previous = duels.hub?.previous {
                            Button(L10n.text("VER RESULTADO ANTERIOR")) { store.push(.dailyDuel(previous.id)) }.font(MVFont.bold(11))
                        }
                    }.padding(14).comicCard()
                }
                if store.duelCurationAPI != nil {
                    Button { suggestions = true } label: {
                        Label(L10n.text("SUGIRA O PRÓXIMO DUELO"), systemImage: "sparkles").font(MVFont.bold(11)).foregroundStyle(MV.C.muted)
                    }.buttonStyle(.plain)
                }
                if let error = duels.error { PeopleStatusNotice(message: error) { await duels.refresh(force: true) } }
            }
            .sheet(isPresented: $suggestions) { DuelSuggestionsView() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await duels.refresh()
                // One wake at the server deadline while visible; no extra polling loop.
                while !Task.isCancelled, let end = duels.hub?.today?.closesAt {
                    let remaining = end.timeIntervalSince(duels.serverNow)
                    guard remaining > 0 else { return }
                    do { try await Task.sleep(for: .seconds(remaining + 1)) } catch { return }
                    await duels.refresh(force: true)
                }
            }
        }
    }
    private func side(_ title: String, color: Color) -> some View {
        Text(title).font(MVFont.bold(14)).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 72).padding(8)
            .background(color.opacity(0.15)).overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
    }
}
