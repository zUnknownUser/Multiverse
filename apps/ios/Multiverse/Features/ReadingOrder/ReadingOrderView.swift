import SwiftUI

struct ReadingOrderView: View {
    let orderID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            ReadingOrdersStatus().padding(.horizontal, MV.pad)
            if let order = store.readingOrders.first(where: { $0.id == orderID }), let uni = store.universe(order.uni) {
                let progress = store.orderProgress(order)
                VStack(alignment: .leading, spacing: 20) {
                    hero(order: order, uni: uni, progress: progress).padding(.horizontal, MV.pad)
                    steps(order: order, uni: uni).padding(.horizontal, MV.pad)
                }
                .padding(.bottom, 24)
            } else if store.readingOrderStore?.loading != true {
                Text(L10n.text("Esta ordem não está disponível. Atualize para ver os percursos atuais."))
                    .font(MVFont.body(14)).foregroundStyle(MV.C.muted).padding(MV.pad)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.readingOrderStore?.refresh(); await store.refreshActivity()
        }
        .refreshable { await store.readingOrderStore?.refresh(); await store.refreshActivity() }
    }

    @ViewBuilder
    private func hero(order: ReadingOrder, uni: Universe, progress: (done: Int, total: Int)) -> some View {
        let voted = store.isOrderVoted(order.id)
        let following = store.isFollowingOrder(order.id)

        VStack(alignment: .leading, spacing: 12) {
            Text(store.readingOrderStore == nil ? L10n.format("ORDEM DA COMUNIDADE · %1$@", uni.name.uppercased()) : L10n.format("ORDEM EDITORIAL · %1$@", uni.name.uppercased())).kicker(11).foregroundStyle(uni.inkColor.opacity(0.85))
            Text(order.title).font(MVFont.display(26, width: 118)).foregroundStyle(uni.inkColor)
            if let followers = order.followers {
                Text(L10n.format("Multiverse · %1$@ obras · %2$@ seguem", String(order.steps.count), String(followers)))
                    .font(MVFont.body(12, weight: 600)).foregroundStyle(uni.inkColor.opacity(0.85))
            } else if let by = store.user(order.by) {
                Text(L10n.format("por %1$@ · %2$@ itens · %3$@ seguem", String(describing: by.handle), String(describing: order.steps.count), String(describing: Logic.fmt(Int((Double(order.votes) / 3).rounded())))))
                    .font(MVFont.body(12, weight: 600)).foregroundStyle(uni.inkColor.opacity(0.85))
            }

            if let description = order.description {
                Text(description).font(MVFont.body(13, weight: 500)).foregroundStyle(uni.inkColor)
                Text(L10n.text("Registre cada obra no diário para avançar. Releituras não contam duas vezes."))
                    .font(MVFont.body(11)).foregroundStyle(uni.inkColor.opacity(0.85))
            }
            if store.readingOrderStore == nil || store.activityLoadError == nil {
            VStack(alignment: .leading, spacing: 6) {
                ComicProgress(value: progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0, fill: uni.inkColor, height: 10)
                Text(L10n.format("%1$@ de %2$@", String(describing: progress.done), String(describing: progress.total))).font(MVFont.bold(12)).foregroundStyle(uni.inkColor)
            }

            if store.readingOrderStore != nil, let next = order.steps.first(where: { !store.isOrderStepRead($0) }), let item = store.item(next) {
                Button { store.push(.item(next)) } label: {
                    HStack { Text(L10n.format("PRÓXIMA LEITURA · %1$@", item.title)).font(MVFont.bold(12)).multilineTextAlignment(.leading); Spacer(); Image(systemName: "arrow.right") }
                        .foregroundStyle(uni.inkColor)
                }.buttonStyle(.plain)
            }
            }
            HStack(spacing: 10) {
                Text("▲ \(Logic.fmt(store.orderVoteCount(order)))")
                    .font(MVFont.bold(14))
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .foregroundStyle(voted ? uni.inkColor : uni.color)
                    .background(voted ? uni.color : uni.inkColor)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .burstOnTap("BOOM!", color: MV.C.accent, when: !voted) {
                        store.voteOrder(order.id)
                    }
                    .allowsHitTesting(store.readingOrderStore?.canMutate ?? true)

                Text(following ? L10n.text("✓ SEGUINDO") : L10n.text("SEGUIR ORDEM"))
                    .font(MVFont.bold(13))
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .foregroundStyle(following ? uni.inkColor : uni.color)
                    .background(following ? uni.color : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(uni.inkColor, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .contentShape(Rectangle())
                    .onTapGesture { store.toggleOrderFollow(order.id) }
                    .allowsHitTesting(store.readingOrderStore?.canMutate ?? true)
            }
        }
        .padding(16)
        .background(uni.color)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xxl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xxl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .background(RoundedRectangle(cornerRadius: MV.R.xxl).fill(MV.C.shadow).offset(x: MV.Shadow.l, y: MV.Shadow.l))
    }

    @ViewBuilder
    private func steps(order: ReadingOrder, uni: Universe) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(order.steps.enumerated()), id: \.offset) { index, itemID in
                if let item = store.item(itemID) {
                    StepRow(number: index + 1, item: item, uni: uni)
                } else if store.readingOrderStore != nil {
                    Text(L10n.text("Uma obra deste percurso mudou. Atualize o catálogo para continuar."))
                        .font(MVFont.body(13)).foregroundStyle(MV.C.muted)
                    Button(L10n.text("ATUALIZAR CATÁLOGO")) { Task { await store.reloadAccount(); await store.readingOrderStore?.refresh() } }.font(MVFont.bold(12))
                }
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let item: Item
    let uni: Universe
    @Environment(AppStore.self) private var store

    var body: some View {
        let seen = store.isOrderStepRead(item.id)
        HStack(spacing: 12) {
            Text("\(number)").font(MVFont.black(18)).foregroundStyle(MV.C.muted).frame(width: 26)

            Button { store.push(.item(item.id)) } label: {
                PosterView(item: item, universe: uni, width: 32, height: 48, titleSize: 7, showLabel: false)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(MVFont.bold(14))
                    .strikethrough(seen)
                    .foregroundStyle(MV.C.ink)
                Text("\(L10n.text(item.type)) · \(item.year.description) · ★ \(L10n.decimal(item.avg))")
                    .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
            }
            Spacer()

            ZStack {
                Circle().fill(seen ? uni.color : MV.C.card)
                if seen { Text("✓").font(MVFont.black(15)).foregroundStyle(uni.inkColor) }
            }
            .frame(width: 34, height: 34)
            .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .contentShape(Circle())
            .accessibilityLabel(store.readingOrderStore == nil ? L10n.text("Marcar como visto") : (seen ? L10n.text("Registrada no diário") : L10n.text("Registrar no diário")))
            .onTapGesture {
                if store.readingOrderStore != nil {
                    if seen { store.push(.item(item.id)) } else { store.openLog(for: item.id) }
                } else { store.toggleSeen(item.id) }
            }
        }
        .padding(.vertical, 6)
    }
}

struct ReadingOrdersStatus: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if let remote = store.readingOrderStore {
            if remote.loading && remote.version == nil { ProgressView().frame(maxWidth: .infinity) }
            if remote.mutating { ProgressView().frame(maxWidth: .infinity) }
            if let error = remote.error {
                PeopleStatusNotice(message: error) {
                    if remote.pending != nil { await remote.retry() } else { await remote.refresh() }
                }
            }
            if let error = store.activityLoadError ?? store.activityRefreshError {
                PeopleStatusNotice(message: error) { await store.refreshActivity() }
            }
        }
    }
}
