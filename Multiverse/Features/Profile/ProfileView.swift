import SwiftUI

struct ProfileView: View {
    let userID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let isRoot = store.tab == .profile && userID == store.meID && store.profilePath.isEmpty
        ScreenScaffold(showBack: !isRoot, onBack: { dismiss() }) {
            let data = store.profileData(for: userID)
            VStack(alignment: .leading, spacing: 22) {
                hero(data: data)
                    .padding(.horizontal, MV.pad)

                if data.isMe {
                    WrappedPromoCard()
                        .padding(.horizontal, MV.pad)
                } else if let compat = data.compatPercent, let line = data.compatLine, let byUni = data.compatByUniverse {
                    AffinityCard(percent: compat, line: line, byUniverse: byUni, agree: data.agreeLine ?? "", disagree: data.disagreeLine ?? "")
                        .padding(.horizontal, MV.pad)
                }

                canonSection(data: data).padding(.horizontal, MV.pad)
                badgesSection(data: data).padding(.horizontal, MV.pad)
                favoritesSection(data: data).padding(.horizontal, MV.pad)
                reviewsSection(data: data).padding(.horizontal, MV.pad)

                if data.isMe {
                    listsSection().padding(.horizontal, MV.pad)
                }
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func hero(data: AppStore.ProfileData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(user: data.user, size: 64, border: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(data.user.name.uppercased())
                        .font(MVFont.archivo(22, weight: 900, width: 110))
                        .foregroundStyle(MV.C.paper)
                    Text("\(data.user.handle) · \(data.user.bio)")
                        .font(MVFont.body(12, weight: 600))
                        .foregroundStyle(MV.C.paper.opacity(0.8))
                }
                Spacer()
                if data.isMe {
                    Button { store.push(.settings) } label: {
                        Text("⚙").font(.system(size: 20))
                            .foregroundStyle(MV.C.paper)
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(MV.C.paper, lineWidth: MV.stroke))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                ForEach(data.stats, id: \.label) { stat in
                    VStack(spacing: 2) {
                        Text(stat.count).font(MVFont.black(17)).foregroundStyle(MV.C.paper)
                        Text(stat.label).font(MVFont.body(9, weight: 700)).foregroundStyle(MV.C.paper.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.paper, lineWidth: MV.stroke))
                }
            }

            if data.isMe {
                HStack(spacing: 10) {
                    Button { store.push(.diary) } label: {
                        Text("DIÁRIO").font(MVFont.bold(12)).foregroundStyle(MV.C.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(MV.C.paper)
                            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    }
                    .buttonStyle(.plain)
                    Button { store.openLogBlank() } label: {
                        Text("+ REGISTRAR").font(MVFont.bold(12)).foregroundStyle(MV.C.paper)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(MV.C.marvel)
                            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.paper, lineWidth: MV.stroke))
                            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                let following = store.isFollowing(userID)
                Text(following ? "SEGUINDO" : "SEGUIR")
                    .font(MVFont.bold(13))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .foregroundStyle(following ? MV.C.paper : MV.C.ink)
                    .background(following ? Color.clear : MV.C.paper)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.paper, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .burstOnTap("ZAP!", color: MV.C.dc, when: !following) {
                        store.toggleFollow(userID)
                    }
            }
        }
        .padding(16)
        .background(MV.C.ink)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xxl))
    }

    @ViewBuilder
    private func canonSection(data: AppStore.ProfileData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CÂNONE CONSUMIDO").font(MVFont.section(17)).foregroundStyle(MV.C.ink)
            VStack(spacing: 8) {
                ForEach(data.progress, id: \.universe.id) { entry in
                    HStack {
                        Text(entry.universe.name).font(MVFont.bold(12)).foregroundStyle(MV.C.ink).frame(width: 70, alignment: .leading)
                        ComicProgress(value: Double(entry.pct) / 100, fill: entry.universe.color, height: 16)
                        Text("\(entry.pct)%").font(MVFont.black(12)).foregroundStyle(MV.C.ink).frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func badgesSection(data: AppStore.ProfileData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SELOS").font(MVFont.section(17)).foregroundStyle(MV.C.ink)
            HStack(spacing: 10) {
                ForEach(data.badges, id: \.universe.id) { badge in
                    BadgeDiamond(badge: badge)
                }
            }
        }
    }

    @ViewBuilder
    private func favoritesSection(data: AppStore.ProfileData) -> some View {
        if !data.favorites.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("FAVORITOS").font(MVFont.section(17)).foregroundStyle(MV.C.ink)
                HStack(spacing: 10) {
                    ForEach(data.favorites) { item in
                        Button { store.push(.item(item.id)) } label: {
                            PosterView(item: item, universe: store.universe(of: item), width: 78, height: 117, titleSize: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func reviewsSection(data: AppStore.ProfileData) -> some View {
        if !data.recentReviews.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("REVIEWS RECENTES").font(MVFont.section(17)).foregroundStyle(MV.C.ink)
                VStack(spacing: 10) {
                    ForEach(data.recentReviews) { review in
                        CompactReviewRow(review: review)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func listsSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LISTAS").font(MVFont.section(17)).foregroundStyle(MV.C.ink)
            VStack(spacing: 10) {
                ForEach(store.profileLists(), id: \.list.id) { entry in
                    ListSummaryRow(list: entry.list, stackColors: entry.stackColors)
                }
            }
        }
    }
}

private struct BadgeDiamond: View {
    let badge: AppStore.BadgeProgress
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(badge.achieved ? badge.universe.color : MV.C.card)
                    .frame(width: 38, height: 38)
                    .rotationEffect(.degrees(45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(MV.C.ink, style: StrokeStyle(lineWidth: MV.stroke, dash: badge.achieved ? [] : [4, 3]))
                            .frame(width: 38, height: 38)
                            .rotationEffect(.degrees(45))
                    )
                Text(badge.achieved ? "★" : "?")
                    .font(MVFont.black(14))
                    .foregroundStyle(badge.achieved ? badge.universe.inkColor : MV.C.muted)
            }
            .opacity(badge.achieved ? 1 : 0.75)
            Text(badge.achieved ? "Conquistado" : "faltam \(badge.remainingPct)%")
                .font(MVFont.body(9, weight: 700))
                .foregroundStyle(MV.C.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CompactReviewRow: View {
    let review: Review
    @Environment(AppStore.self) private var store

    var body: some View {
        guard let item = store.item(review.item) else { return AnyView(EmptyView()) }
        let uni = store.universe(of: item)
        return AnyView(
            HStack(alignment: .top, spacing: 10) {
                Button { store.push(.item(item.id)) } label: {
                    PosterView(item: item, universe: uni, width: 40, height: 60, titleSize: 8, showLabel: false)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 4) {
                    StarsText(rating: review.rating, color: uni.color, size: 13)
                    Text(review.text).font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.ink).lineLimit(2)
                    Text("♥ \(Logic.fmt(store.reviewLikeCount(review))) · \(review.comments.count) comentários")
                        .font(MVFont.body(10, weight: 700)).foregroundStyle(MV.C.muted)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { store.push(.review(review.id)) }
        )
    }
}

private struct ListSummaryRow: View {
    let list: LoreList
    let stackColors: [Color]
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ForEach(Array(stackColors.enumerated()), id: \.offset) { i, c in
                    RoundedRectangle(cornerRadius: MV.R.sm)
                        .fill(c)
                        .frame(width: 34, height: 51)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: 1.5))
                        .offset(x: CGFloat(i) * -14)
                }
            }
            .frame(width: 34 + CGFloat(max(0, stackColors.count - 1)) * 14, height: 51, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(list.title).font(MVFont.bold(13)).foregroundStyle(MV.C.ink).lineLimit(2)
                Text("\(list.items.count) itens · ♥ \(Logic.fmt(store.listLikeCount(list))) · \(list.comments) comentários")
                    .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { store.push(.list(list.id)) }
    }
}
