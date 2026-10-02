import SwiftUI

private enum UniverseTab: String, CaseIterable {
    case geral = "Geral", linha = "Linha do tempo", ordens = "Ordens", pers = "Personagens", salas = "Salas"
}

struct UniverseView: View {
    let universeID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var tab: UniverseTab = .geral

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            if let uni = store.universe(universeID) {
                VStack(alignment: .leading, spacing: 20) {
                    hero(uni: uni).padding(.horizontal, MV.pad)
                    CommunityLink(universe: universeID).padding(.horizontal, MV.pad)
                    tabBar.padding(.horizontal, MV.pad)

                    switch tab {
                    case .geral: GeneralTabContent(universeID: universeID)
                    case .linha: TimelineTabContent(universeID: universeID)
                    case .ordens: OrdersTabContent(universeID: universeID)
                    case .pers: CharactersTabContent(universeID: universeID)
                    case .salas: RoomsTabContent(universeID: universeID)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private func hero(uni: Universe) -> some View {
        let pct = store.universePercent(uni.id)
        ZStack(alignment: .topLeading) {
            uni.color
            Halftone(color: uni.inkColor.opacity(0.18))
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.format("UNIVERSO · %1$@", String(describing: uni.canon))).kicker(11).foregroundStyle(uni.inkColor.opacity(0.85))
                Text(uni.name.uppercased())
                    .font(MVFont.display(38, width: 125))
                    .foregroundStyle(uni.inkColor)
                Text(uni.tagline)
                    .font(MVFont.body(13, weight: 600))
                    .foregroundStyle(uni.inkColor.opacity(0.9))
                VStack(alignment: .leading, spacing: 6) {
                    ComicProgress(value: Double(pct) / 100, fill: uni.inkColor, height: 10)
                    Text(L10n.format("%1$@%% visto", String(describing: pct))).font(MVFont.bold(12)).foregroundStyle(uni.inkColor)
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xxl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xxl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .background(RoundedRectangle(cornerRadius: MV.R.xxl).fill(MV.C.shadow).offset(x: MV.Shadow.l, y: MV.Shadow.l))
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(UniverseTab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    Text(L10n.text(t.rawValue).uppercased())
                        .font(MVFont.bold(11))
                        .padding(.horizontal, 10).padding(.vertical, 9)
                        .foregroundStyle(tab == t ? MV.C.paper : MV.C.ink)
                        .background(tab == t ? MV.C.ink : MV.C.card)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct GeneralTabContent: View {
    let universeID: String
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                ForEach(store.universeStats(universeID), id: \.label) { stat in
                    VStack(spacing: 2) {
                        Text(stat.count).font(MVFont.black(16)).foregroundStyle(MV.C.ink)
                        Text(stat.label.uppercased()).font(MVFont.body(9, weight: 700)).foregroundStyle(MV.C.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .comicCard(shadow: MV.Shadow.s)
                }
            }
            .padding(.horizontal, MV.pad)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: L10n.text("Mais bem avaliados")).padding(.horizontal, MV.pad)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(store.topRatedItems(in: universeID)) { item in
                            Button { store.push(.item(item.id)) } label: {
                                PosterView(item: item, universe: store.universe(of: item), width: 96, height: 144, titleSize: 11)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, MV.pad)
                }
                .scrollIndicators(.hidden)
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: L10n.text("Reviews populares")).padding(.horizontal, MV.pad)
                VStack(spacing: 12) {
                    ForEach(store.reviewsIn(universe: universeID, limit: 3)) { review in
                        FeedReviewCard(review: review)
                    }
                }
                .padding(.horizontal, MV.pad)
            }
        }
    }
}

private struct TimelineTabContent: View {
    let universeID: String
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let chips = store.timelineFriendChips(for: universeID)
            if !chips.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("ONDE SEU PESSOAL ESTÁ")).kicker(11).foregroundStyle(MV.C.muted)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(chips, id: \.user.id) { chip in
                                HStack(spacing: 6) {
                                    AvatarView(user: chip.user, size: 22)
                                    Text(chip.whereLabel).font(MVFont.bold(11)).foregroundStyle(MV.C.ink)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Capsule().fill(MV.C.card))
                                .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, MV.pad)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(store.timelineRows(for: universeID).enumerated()), id: \.element.id) { i, row in
                    TimelineRailRow(row: row, universeID: universeID)
                }
            }
            .padding(.horizontal, MV.pad)
        }
    }
}

private struct TimelineRailRow: View {
    let row: AppStore.TimelineRow
    let universeID: String
    @Environment(AppStore.self) private var store

    var body: some View {
        guard let uni = store.universe(universeID) else { return AnyView(EmptyView()) }
        return AnyView(
            Button { store.push(.item(row.item.id)) } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle().fill(row.isSeen ? uni.color : MV.C.card)
                            if row.isSeen { Text("✓").font(MVFont.black(11)).foregroundStyle(uni.inkColor) }
                        }
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        Rectangle().fill(MV.C.ink).frame(width: 2).frame(maxHeight: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.entry.era.uppercased()).kicker(10).foregroundStyle(MV.C.muted)
                        Text(row.item.title).font(MVFont.black(17)).foregroundStyle(MV.C.ink)
                        Text("[\(L10n.text(row.item.type))] \(row.entry.note) · ★ \(L10n.decimal(row.item.avg))")
                            .font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.muted)
                        if !row.friends.isEmpty {
                            HStack(spacing: -8) {
                                ForEach(row.friends) { f in AvatarView(user: f, size: 22) }
                            }
                            Text(row.friendsLabel).font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                        }
                    }
                    .padding(.bottom, 18)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        )
    }
}

private struct OrdersTabContent: View {
    let universeID: String
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Ordens montadas e votadas pela comunidade. A mais votada sobe pro topo."))
                .font(MVFont.body(13, weight: 600)).foregroundStyle(MV.C.muted)
            VStack(spacing: 12) {
                ForEach(store.ordersList(in: universeID)) { order in
                    OrderSummaryCard(order: order)
                }
            }
        }
        .padding(.horizontal, MV.pad)
    }
}

private struct OrderSummaryCard: View {
    let order: ReadingOrder
    @Environment(AppStore.self) private var store

    var body: some View {
        guard let uni = store.universe(order.uni) else { return AnyView(EmptyView()) }
        let voted = store.isOrderVoted(order.id)
        let progress = store.orderProgress(order)

        return AnyView(
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 2) {
                    Text("▲").font(MVFont.black(16))
                    Text("\(Logic.fmt(store.orderVoteCount(order)))").font(MVFont.black(11))
                }
                .foregroundStyle(voted ? uni.inkColor : MV.C.ink)
                .frame(width: 52, height: 52)
                .background(voted ? uni.color : MV.C.card)
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                .burstOnTap("BOOM!", color: MV.C.wow, when: !voted) {
                    store.voteOrder(order.id)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(order.title).font(MVFont.bold(15)).foregroundStyle(MV.C.ink)
                    if let by = store.user(order.by) {
                        Text(L10n.format("por %1$@ · %2$@ itens · %3$@ seguem", String(describing: by.handle), String(describing: order.steps.count), String(describing: Logic.fmt(Int((Double(order.votes) / 3).rounded())))))
                            .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                    }
                    HStack(spacing: 8) {
                        ComicProgress(value: progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0, fill: uni.color, height: 10)
                        Text("\(progress.done)/\(progress.total)").font(MVFont.bold(11)).foregroundStyle(MV.C.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .comicCard(shadow: MV.Shadow.s)
            .contentShape(Rectangle())
            .onTapGesture { store.push(.order(order.id)) }
        )
    }
}

private struct CharactersTabContent: View {
    let universeID: String
    @Environment(AppStore.self) private var store
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(store.charactersList(in: universeID)) { item in
                Button { store.push(.item(item.id)) } label: {
                    VStack(spacing: 6) {
                        let uni = store.universe(of: item)
                        let p = Logic.posterColors(item: item, universe: uni)
                        ZStack { p.bg; Halftone() }
                            .frame(width: 92, height: 92)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        Text(item.title).font(MVFont.bold(12)).foregroundStyle(MV.C.ink).lineLimit(1)
                        Text(L10n.format("★ %1$@ · %2$@ registros", String(describing: L10n.decimal(item.avg)), String(describing: Logic.fmt(Logic.logCount(item)))))
                            .font(MVFont.body(9, weight: 600)).foregroundStyle(MV.C.muted)
                            .multilineTextAlignment(.center).lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MV.pad)
    }
}

private struct RoomsTabContent: View {
    let universeID: String
    @Environment(AppStore.self) private var store

    private var rooms: [Room] {
        store.rooms.filter { store.item($0.itemID)?.uni == universeID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if rooms.isEmpty {
                Text(L10n.text("Nenhuma sala aberta nesse universo agora."))
                    .font(MVFont.body(13, weight: 600)).foregroundStyle(MV.C.muted)
            } else {
                ForEach(rooms) { room in
                    if let item = store.item(room.itemID) {
                        Button { store.push(.room(item.id)) } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                                    Text("\(Logic.fmt(room.onlineCount)) online").font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                                }
                                Spacer()
                                Text("→").foregroundStyle(MV.C.muted)
                            }
                            .padding(12)
                            .comicCard(shadow: MV.Shadow.s)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, MV.pad)
    }
}
