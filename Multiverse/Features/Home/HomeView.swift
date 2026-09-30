import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 26) {
                header.padding(.horizontal, MV.pad)
                if store.isShieldActive { ShieldStatusBanner().padding(.horizontal, MV.pad) }
                wrappedBanner.padding(.horizontal, MV.pad)
                universeGrid.padding(.horizontal, MV.pad)
                if !store.clubs.isEmpty { MyClubsCard().padding(.horizontal, MV.pad) }
                trendingSection
                DuelCard()
                    .padding(.horizontal, MV.pad)
                DebateCard()
                    .padding(.horizontal, MV.pad)
                theoriesAndPredictionsRow.padding(.horizontal, MV.pad)
                feedSection.padding(.horizontal, MV.pad)
                suggestionsSection
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MULTIVERSE")
                    .font(MVFont.display(30, width: 125))
                    .tracking(-0.4)
                    .foregroundStyle(MV.C.ink)
                Text("\(store.friendsCount) amigos · 3 universos")
                    .kicker(11).foregroundStyle(MV.C.muted)
            }
            Spacer()
            HStack(spacing: 10) {
                Button { store.openNotifications() } label: {
                    ZStack(alignment: .topTrailing) {
                        Text("🔔").font(.system(size: 20))
                            .frame(width: 40, height: 40)
                            .background(MV.C.card)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        if store.unreadCount > 0 {
                            Text("\(store.unreadCount)")
                                .font(MVFont.black(9))
                                .foregroundStyle(MV.C.card)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(MV.C.marvel))
                                .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: 1))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.unreadCount > 0 ? "Avisos, \(store.unreadCount) não lidos" : "Avisos")

                Button { store.openMyProfile() } label: {
                    let me = store.user(store.meID)!
                    ZStack {
                        Color(hex: me.avatarColor)
                        Text(Logic.initials(me.name)).font(MVFont.black(14)).foregroundStyle(Logic.inkOn(hex: me.avatarColor))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Seu perfil")
            }
        }
        .padding(.top, 10)
    }

    private var wrappedBanner: some View {
        Button { store.push(.wrapped) } label: {
            ZStack(alignment: .leading) {
                MV.C.ink
                Halftone(color: MV.C.paper.opacity(0.12))
                HStack(spacing: 12) {
                    Text("NOVO")
                        .font(MVFont.black(10)).tracking(0.5)
                        .foregroundStyle(MV.C.card)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: MV.R.xs).fill(MV.C.marvel))
                        .overlay(RoundedRectangle(cornerRadius: MV.R.xs).strokeBorder(MV.C.paper, lineWidth: 1.5))
                        .rotationEffect(.degrees(-4))
                    Text("Seu setembro no Multiverse está pronto")
                        .font(MVFont.bold(13))
                        .foregroundStyle(MV.C.paper)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Text("→").font(MVFont.black(18)).foregroundStyle(MV.C.paper)
                }
                .padding(14)
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: MV.R.lg))
            .overlay(RoundedRectangle(cornerRadius: MV.R.lg).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        }
        .buttonStyle(.plain)
    }

    private var universeGrid: some View {
        HStack(spacing: 10) {
            ForEach(store.universes) { u in
                UniverseMiniCard(universe: u)
            }
        }
    }

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Em alta no seu círculo", trailing: "VER TUDO") {
                store.goToTab(.search)
            }
            .padding(.horizontal, MV.pad)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(StaticContent.trendingItemIDs, id: \.self) { id in
                        if let item = store.item(id) {
                            TrendingPosterCard(item: item)
                        }
                    }
                }
                .padding(.horizontal, MV.pad)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("DO SEU PESSOAL").font(MVFont.section(19)).foregroundStyle(MV.C.ink)
                Spacer()
                Text("seguindo \(store.friendsCount)").kicker(11).foregroundStyle(MV.C.muted)
            }

            let feed = store.homeFeed()
            if feed.isEmpty {
                emptyFeed
            } else {
                VStack(spacing: 12) {
                    ForEach(feed) { review in
                        FeedReviewCard(review: review)
                    }
                }
            }
        }
    }

    private var emptyFeed: some View {
        VStack(spacing: 6) {
            Text("SILÊNCIO NO MULTIVERSE").font(MVFont.section(16)).foregroundStyle(MV.C.ink)
            Text("Seu feed ganha vida quando você segue gente. Comece pelos loristas abaixo.")
                .font(MVFont.body(13)).foregroundStyle(MV.C.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .comicCard(shadow: 0, dashed: true)
    }

    private var theoriesAndPredictionsRow: some View {
        HStack(spacing: 10) {
            promoTile(title: "TEORIAS", subtitle: "\(store.theoriesFiltered(.open).count) em aberto", bg: MV.C.dc) { store.push(.theories) }
            promoTile(title: "PREVISÕES", subtitle: "\(store.predictionPoints) pts", bg: MV.C.wow, fg: MV.C.ink) { store.push(.predictions) }
        }
    }

    private func promoTile(title: String, subtitle: String, bg: Color, fg: Color = MV.C.paper, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MVFont.black(15)).foregroundStyle(fg)
                Text(subtitle).font(MVFont.body(11, weight: 700)).foregroundStyle(fg.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        }
        .buttonStyle(.plain)
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LORISTAS PRA SEGUIR").font(MVFont.section(19)).foregroundStyle(MV.C.ink)
                Text("Quanto mais gente você segue, melhor fica o seu feed.")
                    .font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.muted)
            }
            .padding(.horizontal, MV.pad)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(StaticContent.suggestionUserIDs, id: \.self) { id in
                        if let user = store.user(id) {
                            SuggestionCard(user: user)
                        }
                    }
                }
                .padding(.horizontal, MV.pad)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct UniverseMiniCard: View {
    let universe: Universe
    @Environment(AppStore.self) private var store

    var body: some View {
        let pct = store.universePercent(universe.id)
        Button { store.push(.universe(universe.id)) } label: {
            ZStack(alignment: .topLeading) {
                universe.color
                Halftone(color: universe.inkColor.opacity(0.18))
                VStack(alignment: .leading, spacing: 6) {
                    Text(universe.name.uppercased())
                        .font(MVFont.black(14))
                        .foregroundStyle(universe.inkColor)
                    Text("\(Logic.fmt(universe.live)) ativos agora")
                        .font(MVFont.body(9, weight: 700))
                        .foregroundStyle(universe.inkColor.opacity(0.85))
                    Spacer(minLength: 0)
                    Text("\(pct)%")
                        .font(MVFont.black(22))
                        .foregroundStyle(universe.inkColor)
                    ComicProgress(value: Double(pct) / 100, fill: universe.inkColor, height: 6)
                }
                .padding(10)
            }
            .frame(height: 104)
            .frame(maxWidth: .infinity)
            .comicCard(bg: universe.color, radius: MV.R.xl, shadow: MV.Shadow.s)
        }
        .buttonStyle(.plain)
    }
}

private struct TrendingPosterCard: View {
    let item: Item
    @Environment(AppStore.self) private var store

    var body: some View {
        let uni = store.universe(of: item)
        Button { store.push(.item(item.id)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                PosterView(item: item, universe: uni, width: 96, height: 144, titleSize: 11)
                Text("★ \(String(format: "%.1f", item.avg).replacingOccurrences(of: ".", with: ","))")
                    .font(MVFont.bold(11)).foregroundStyle(MV.C.ink)
                Text(store.trendingBuzz(for: item))
                    .font(MVFont.body(10, weight: 600)).foregroundStyle(MV.C.muted)
                    .lineLimit(1)
            }
            .frame(width: 96)
        }
        .buttonStyle(.plain)
    }
}

private struct SuggestionCard: View {
    let user: User
    @Environment(AppStore.self) private var store

    var body: some View {
        let following = store.isFollowing(user.id)
        VStack(spacing: 8) {
            Button { store.openUserProfile(user.id) } label: { AvatarView(user: user, size: 52) }
                .buttonStyle(.plain)
            Text(user.name).font(MVFont.bold(13)).foregroundStyle(MV.C.ink).lineLimit(1)
            Text(user.bio).font(MVFont.body(11, weight: 500)).foregroundStyle(MV.C.muted)
                .multilineTextAlignment(.center).lineLimit(2)
            if let uni = store.universe(user.badgeUniverse) {
                Text("\(Logic.compat(user.id))% afinidade")
                    .font(MVFont.black(9)).tracking(0.3)
                    .foregroundStyle(uni.inkColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(uni.color))
                    .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: 1.5))
            }
            Text(following ? "Seguindo" : "Seguir")
                .font(MVFont.bold(12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(following ? MV.C.ink : MV.C.paper)
                .background(following ? MV.C.card : MV.C.ink)
                .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(Capsule())
                .burstOnTap("ZAP!", color: MV.C.dc, when: !following) {
                    store.toggleFollow(user.id)
                }
        }
        .padding(12)
        .frame(width: 138)
        .comicCard()
    }
}
