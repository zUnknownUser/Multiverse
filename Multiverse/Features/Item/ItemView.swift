import SwiftUI

struct ItemView: View {
    let itemID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reviewFilter: ReviewFilter = .popular

    private enum ReviewFilter: String { case popular = "Populares", friends = "Amigos" }

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            if let item = store.item(itemID) {
                let uni = store.universe(of: item)
                VStack(alignment: .leading, spacing: 22) {
                    topSection(item: item, uni: uni).padding(.horizontal, MV.pad)
                    actionsRow(item: item, uni: uni).padding(.horizontal, MV.pad)
                    friendsSection(item: item, uni: uni).padding(.horizontal, MV.pad)
                    Text(item.desc).font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)
                        .padding(.horizontal, MV.pad)
                    WhereToWatchSection(itemID: item.id).padding(.horizontal, MV.pad)
                    canonSection(item: item, uni: uni).padding(.horizontal, MV.pad)
                    essentialSection(item: item, uni: uni).padding(.horizontal, MV.pad)
                    histogramSection(item: item, uni: uni).padding(.horizontal, MV.pad)
                    timelineSection(item: item, uni: uni).padding(.horizontal, MV.pad)
                    connectionsSection(item: item).padding(.horizontal, MV.pad)
                    reviewsSection(item: item).padding(.horizontal, MV.pad)
                }
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Topo

    @ViewBuilder
    private func topSection(item: Item, uni: Universe) -> some View {
        HStack(alignment: .top, spacing: 14) {
            PosterView(item: item, universe: uni, width: 118, height: 177, titleSize: 15, shadow: MV.Shadow.l)
            VStack(alignment: .leading, spacing: 8) {
                Button { store.push(.universe(uni.id)) } label: {
                    Text(uni.name.uppercased())
                        .font(MVFont.black(10)).tracking(0.4)
                        .foregroundStyle(uni.inkColor)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(uni.color))
                        .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: 1.5))
                }
                .buttonStyle(.plain)

                Text(item.title)
                    .font(MVFont.archivo(22, weight: 900, width: 105))
                    .foregroundStyle(MV.C.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(item.type) · \(item.year.description) · \(item.canon)")
                    .font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.muted)

                Text(String(format: "%.1f", item.avg).replacingOccurrences(of: ".", with: ","))
                    .font(MVFont.black(30)).foregroundStyle(MV.C.ink)

                Text("\(Logic.fmt(Logic.logCount(item))) registros · \(Logic.fmt(Logic.reviewCount(item))) reviews")
                    .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
            }
        }
    }

    // MARK: Ações

    @ViewBuilder
    private func actionsRow(item: Item, uni: Universe) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(store.logActionLabel(for: item).uppercased())
                    .font(MVFont.bold(12))
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .foregroundStyle(uni.inkColor)
                    .background(uni.color)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .contentShape(Rectangle())
                    .onTapGesture { store.openLog(for: item.id) }
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity)

                let wanted = store.isWanted(item.id)
                Text(wanted ? "✓ NA LISTA" : "+ QUERO")
                    .font(MVFont.bold(11))
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .foregroundStyle(wanted ? MV.C.paper : MV.C.ink)
                    .background(wanted ? MV.C.ink : MV.C.card)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .contentShape(Rectangle())
                    .onTapGesture { store.toggleWanted(item.id) }

                let liked = store.isItemLiked(item.id)
                Text("♥ CURTIR")
                    .font(MVFont.bold(11))
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .foregroundStyle(liked ? MV.C.card : MV.C.ink)
                    .background(liked ? MV.C.marvel : MV.C.card)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .contentShape(Rectangle())
                    .onTapGesture { store.toggleItemLiked(item.id) }
            }
            if let mine = store.myDiaryEntry(for: item.id) {
                HStack(spacing: 6) {
                    Text("Sua nota:").font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.muted)
                    StarsText(rating: mine.rating, color: uni.color, size: 14)
                }
            }
        }
    }

    // MARK: Amigos

    @ViewBuilder
    private func friendsSection(item: Item, uni: Universe) -> some View {
        let friends = store.friendRatings(for: item)
        if !friends.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("AMIGOS QUE REGISTRARAM").kicker(11).foregroundStyle(MV.C.muted)
                    Spacer()
                    if let avg = store.friendAvgLabel(for: item) {
                        Text("média deles \(avg)").font(MVFont.body(11, weight: 700)).foregroundStyle(MV.C.muted)
                    }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(friends, id: \.user.id) { entry in
                            Button { store.openUserProfile(entry.user.id) } label: {
                                VStack(spacing: 4) {
                                    AvatarView(user: entry.user, size: 40)
                                    StarsText(rating: entry.rating, color: uni.color, size: 11)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: Cânone

    @ViewBuilder
    private func canonSection(item: Item, uni: Universe) -> some View {
        let info = store.canonInfo(for: item)
        let colors = store.canonColors(for: info.status)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(info.status.uppercased())
                    .font(MVFont.black(11)).tracking(0.4)
                    .foregroundStyle(colors.fg)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(colors.bg)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.sm))
                    .rotationEffect(.degrees(-2))
                Text(info.note).font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Conta como cânone pra você?").font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                let percents = store.canonPercents(for: item)
                let chosen = store.canonVotes[item.id]
                HStack(spacing: 8) {
                    ForEach(Array(["Sim", "Não", "Em parte"].enumerated()), id: \.offset) { i, label in
                        CanonVoteButton(label: label, index: i, percent: percents?[i], chosen: chosen == i, color: uni.color, textColor: uni.inkColor) {
                            store.voteCanon(item.id, index: i)
                        }
                    }
                }
            }
        }
    }

    // MARK: Voto da comunidade (essencial)

    @ViewBuilder
    private func essentialSection(item: Item, uni: Universe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Voto da comunidade").kicker(11).foregroundStyle(uni.inkColor)
                Spacer()
                Text(store.essentialTotalLabel(for: item)).font(MVFont.body(11, weight: 700)).foregroundStyle(uni.inkColor.opacity(0.85))
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(uni.color)

            VStack(alignment: .leading, spacing: 8) {
                Text("Essencial pra entender \(uni.name)?").font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                let percents = store.essentialPercents(for: item)
                let chosen = store.essentialVotes[item.id]
                ForEach(Array(["Essencial", "Opcional", "Pode pular"].enumerated()), id: \.offset) { i, label in
                    EssentialVoteRow(label: label, index: i, percent: percents?[i], chosen: chosen == i, color: uni.color) {
                        store.voteEssential(item.id, index: i)
                    }
                }
            }
            .padding(12)
        }
        .background(MV.C.card)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
    }

    // MARK: Histograma

    @ViewBuilder
    private func histogramSection(item: Item, uni: Universe) -> some View {
        let hist = Logic.ratingHistogram(item)
        let maxVal = max(hist.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTAS DA COMUNIDADE").kicker(11).foregroundStyle(MV.C.muted)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(hist.enumerated()), id: \.offset) { i, v in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i >= 8 ? uni.color : MV.C.card)
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(MV.C.ink, lineWidth: 1))
                        .frame(height: max(4, 60 * CGFloat(v) / CGFloat(maxVal)))
                }
            }
            .frame(height: 60, alignment: .bottom)
            HStack {
                Text("½").font(MVFont.bold(11)).foregroundStyle(MV.C.muted)
                Spacer()
                Text("★★★★★").font(MVFont.bold(11)).foregroundStyle(MV.C.muted)
            }
        }
    }

    // MARK: Linha do tempo

    @ViewBuilder
    private func timelineSection(item: Item, uni: Universe) -> some View {
        let neighbors = store.timelineNeighbors(for: item)
        if neighbors.current != nil {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Na linha do tempo", trailing: "VER TUDO") {
                    store.push(.universe(uni.id))
                }
                HStack(spacing: 8) {
                    TimelineNeighborColumn(label: "Antes", entry: neighbors.before, isCurrent: false, uni: uni)
                    TimelineNeighborColumn(label: "Aqui · \(neighbors.current?.era ?? "")", entry: neighbors.current, isCurrent: true, uni: uni)
                    TimelineNeighborColumn(label: "Depois", entry: neighbors.after, isCurrent: false, uni: uni)
                }
            }
        }
    }

    // MARK: Mapa de conexões

    @ViewBuilder
    private func connectionsSection(item: Item) -> some View {
        let connected = store.connectedItems(for: item.id)
        if !connected.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("MAPA DE CONEXÕES").kicker(11).foregroundStyle(MV.C.muted)
                ConnectionMapView(center: item, connected: connected)
            }
        }
    }

    // MARK: Reviews

    @ViewBuilder
    private func reviewsSection(item: Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("REVIEWS").font(MVFont.section(19)).foregroundStyle(MV.C.ink)
                Spacer()
                HStack(spacing: 6) {
                    ForEach([ReviewFilter.popular, .friends], id: \.self) { f in
                        Button { reviewFilter = f } label: {
                            Text(f.rawValue)
                                .font(MVFont.bold(11))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .foregroundStyle(reviewFilter == f ? MV.C.paper : MV.C.ink)
                                .background(reviewFilter == f ? MV.C.ink : MV.C.card)
                                .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let revs = Array(store.reviewsForItem(item.id, friendsOnly: reviewFilter == .friends).prefix(5))
            if revs.isEmpty {
                Text("Nenhum amigo escreveu sobre isso ainda. Seja o primeiro.")
                    .font(MVFont.body(13)).foregroundStyle(MV.C.muted)
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .comicCard(shadow: 0, dashed: true)
            } else {
                VStack(spacing: 12) {
                    ForEach(revs) { review in
                        FeedReviewCard(review: review, showFollowingTag: store.isFollowing(review.user))
                    }
                }
            }

            Button { store.push(.correctionForm(item.id)) } label: {
                Text("Sugerir correção").font(MVFont.bold(12)).underline().foregroundStyle(MV.C.ink)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CanonVoteButton: View {
    let label: String
    let index: Int
    let percent: Int?
    let chosen: Bool
    let color: Color
    let textColor: Color
    let action: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(MVFont.bold(12))
            if let percent { Text("\(percent)%").font(MVFont.black(12)) }
        }
        .foregroundStyle(chosen ? textColor : MV.C.ink)
        .frame(maxWidth: .infinity).frame(height: 44)
        .background(chosen ? color : MV.C.card)
        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        .burstOnTap("ZAP!", color: color, when: percent == nil) { action() }
    }
}

private struct EssentialVoteRow: View {
    let label: String
    let index: Int
    let percent: Int?
    let chosen: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                MV.C.ink.opacity(0.1)
                Rectangle().fill(chosen ? color : MV.C.ink.opacity(0.1))
                    .frame(width: geo.size.width * Double(percent ?? 0) / 100)
                    .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5), value: percent)
                HStack {
                    Text(label).font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                    Spacer()
                    if let percent { Text("\(percent)%").font(MVFont.black(13)).foregroundStyle(MV.C.ink) }
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(height: 36)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .burstOnTap("BAM!", color: color, when: percent == nil) { action() }
    }
}

private struct TimelineNeighborColumn: View {
    let label: String
    let entry: TimelineEntry?
    let isCurrent: Bool
    let uni: Universe
    @Environment(AppStore.self) private var store

    var body: some View {
        let item = entry.flatMap { store.item($0.itemId) }
        VStack(spacing: 4) {
            Text(label.uppercased()).font(MVFont.black(9)).tracking(0.3)
                .foregroundStyle(isCurrent ? uni.inkColor : MV.C.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(item?.title ?? "—")
                .font(MVFont.bold(11))
                .foregroundStyle(isCurrent ? uni.inkColor : MV.C.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .frame(minHeight: 64)
        .background(isCurrent ? uni.color : MV.C.card)
        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: isCurrent ? 0 : MV.stroke))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        .contentShape(Rectangle())
        .onTapGesture { if !isCurrent, let item { store.push(.item(item.id)) } }
    }
}
