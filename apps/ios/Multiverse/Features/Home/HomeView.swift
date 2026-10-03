import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 26) {
                header.padding(.horizontal, MV.pad)
                if store.showsDemoFeatures && store.liveEvent != nil { LivePremiereBanner().padding(.horizontal, MV.pad) }
                if store.showsDemoFeatures && store.isShieldActive { ShieldStatusBanner().padding(.horizontal, MV.pad) }
                if store.showsDemoFeatures { wrappedBanner.padding(.horizontal, MV.pad) }
                universeGrid.padding(.horizontal, MV.pad)
                HomeCommunitySection()
                if store.showsDemoFeatures && !store.clubs.isEmpty { MyClubsCard().padding(.horizontal, MV.pad) }
                if !store.homeDiscoveryItems.isEmpty { trendingSection }
                if store.showsDemoFeatures {
                DuelCard()
                    .padding(.horizontal, MV.pad)
                DebateCard()
                    .padding(.horizontal, MV.pad)
                theoriesAndPredictionsRow.padding(.horizontal, MV.pad)
                }
                feedSection.padding(.horizontal, MV.pad)
                if let people = store.people {
                    if let error = people.homeError {
                        PeopleStatusNotice(message: error) { await people.loadHome() }.padding(.horizontal, MV.pad)
                    }
                    if people.isLoadingHome { ProgressView().frame(maxWidth: .infinity) }
                    if let error = people.followError { AuthErrorBanner(message: error).padding(.horizontal, MV.pad) }
                }
                if !store.homeSuggestedPeople.isEmpty { suggestionsSection }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .task {
            await store.library?.refresh()
            await store.notifications?.refresh()
            if store.people?.state == nil { await store.people?.loadHome() }
            await store.social?.loadPrivacy()
            if store.social?.hasLoadedFeed == false { await store.social?.loadFeed() }
        }
        .onChange(of: store.people?.state?.followingIDs) { _, _ in
            store.social?.invalidateFeed()
            Task { await store.social?.loadFeed() }
        }
        .refreshable {
            if let api = store.communityAPI { await store.homeCommunity.load(api: api, filter: .init()) }
            await store.notifications?.refresh()
            await store.refreshActivity()
            await store.people?.loadHome()
            await store.social?.loadFeed()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MULTIVERSE")
                    .font(MVFont.display(30, width: 125))
                    .tracking(-0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(MV.C.ink)
                Text((store.friendsCount == 0 ? L10n.text("Nenhum amigo") : L10n.format("home.friendsCount", store.friendsCount)) + " · " + L10n.format("home.universesCount", store.universes.count))
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
                .accessibilityLabel(store.unreadCount > 0 ? L10n.format("Avisos, %1$@ não lidos", String(describing: store.unreadCount)) : L10n.text("Avisos"))

                if store.showsDemoFeatures || store.directMessages != nil {
                Button { store.push(.messages) } label: {
                    ZStack(alignment: .topTrailing) {
                        Text("✉").font(.system(size: 18, weight: .bold))
                            .frame(width: 40, height: 40)
                            .background(MV.C.card)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        if store.totalUnreadMessages > 0 {
                            Text("\(store.totalUnreadMessages)")
                                .font(MVFont.black(9))
                                .foregroundStyle(MV.C.card)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(MV.C.marvel))
                                .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: 1))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.totalUnreadMessages > 0 ? L10n.format("Mensagens, %1$@ não lidas", String(describing: store.totalUnreadMessages)) : L10n.text("Mensagens"))

                }
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
                .accessibilityLabel(L10n.text("Seu perfil"))
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
                    Text(L10n.text("NOVO"))
                        .font(MVFont.black(10)).tracking(0.5)
                        .foregroundStyle(MV.C.card)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: MV.R.xs).fill(MV.C.marvel))
                        .overlay(RoundedRectangle(cornerRadius: MV.R.xs).strokeBorder(MV.C.paper, lineWidth: 1.5))
                        .rotationEffect(.degrees(-4))
                    Text(L10n.text("Seu setembro no Multiverse está pronto"))
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
            SectionHeader(title: L10n.text(store.usesRemoteCatalog ? "Explore o catálogo" : "Em alta no seu círculo"), trailing: L10n.text("VER TUDO")) {
                store.goToTab(.search)
            }
            .padding(.horizontal, MV.pad)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(store.homeDiscoveryItems) { item in TrendingPosterCard(item: item) }
                }
                .padding(.horizontal, MV.pad)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text(store.usesRemoteActivity && store.social == nil ? "SUAS REVIEWS" : "DO SEU PESSOAL")).font(MVFont.section(19)).foregroundStyle(MV.C.ink)
                Spacer()
                Text(L10n.format("seguindo %1$@", String(describing: store.friendsCount))).kicker(11).foregroundStyle(MV.C.muted)
            }

            if let social = store.social {
                if let error = social.feedError {
                    PeopleStatusNotice(message: error) { await social.loadFeed(more: social.nextCursor != nil && !social.feedIDs.isEmpty) }
                }
                if social.isLoadingFeed { ProgressView().frame(maxWidth: .infinity) }
            }
            let feed = store.homeFeed()
            if feed.isEmpty {
                if store.social == nil || (store.social?.hasLoadedFeed == true && store.social?.feedError == nil) { emptyFeed }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(feed) { review in
                        FeedReviewCard(review: review, showFollowingTag: store.isFollowing(review.user))
                    }
                }
                if let social = store.social, social.nextCursor != nil {
                    PrimaryAuthButton(title: L10n.text("VER MAIS")) { Task { await social.loadFeed(more: true) } }
                        .disabled(social.isLoadingFeed)
                }
            }
        }
    }

    private var emptyFeed: some View {
        VStack(spacing: 6) {
            Text(L10n.text("SILÊNCIO NO MULTIVERSE")).font(MVFont.section(16)).foregroundStyle(MV.C.ink)
            Text(store.homeEmptyFeedMessage)
                .font(MVFont.body(13)).foregroundStyle(MV.C.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .comicCard(shadow: 0, dashed: true)
    }

    private var theoriesAndPredictionsRow: some View {
        HStack(spacing: 10) {
            promoTile(title: L10n.text("TEORIAS"), subtitle: L10n.format("theories.open", store.theoriesFiltered(.open).count), bg: MV.C.dc) { store.push(.theories) }
            promoTile(title: L10n.text("PREVISÕES"), subtitle: "\(store.predictionPoints) pts", bg: MV.C.accent, fg: MV.C.ink) { store.push(.predictions) }
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
                Text(L10n.text("LORISTAS PRA SEGUIR")).font(MVFont.section(19)).foregroundStyle(MV.C.ink)
                Text(L10n.text("Encontre pessoas que também exploram estes universos."))
                    .font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.muted)
            }
            .padding(.horizontal, MV.pad)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(store.homeSuggestedPeople) { user in SuggestionCard(user: user) }
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
                    Text(store.usesRemoteCatalog ? L10n.format("%1$@ itens", String(universe.total)) : L10n.format("%1$@ ativos agora", String(describing: Logic.fmt(universe.live))))
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
                Text(store.usesRemoteCatalog && item.avg == 0 ? L10n.text("Sem notas ainda") : "★ \(L10n.decimal(item.avg))")
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
                Text(L10n.format("%1$@%% afinidade", String(describing: Logic.compat(user.id))))
                    .font(MVFont.black(9)).tracking(0.3)
                    .foregroundStyle(uni.inkColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(uni.color))
                    .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: 1.5))
            }
            Text(store.people?.savingPersonID == user.id ? L10n.text("SALVANDO…") : (following ? L10n.text("Seguindo") : L10n.text("Seguir")))
                .font(MVFont.bold(12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(following ? MV.C.ink : MV.C.paper)
                .background(following ? MV.C.card : MV.C.ink)
                .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(Capsule())
                .burstOnTap("ZAP!", color: MV.C.dc, when: !following && !store.usesRemotePeople) {
                    store.toggleFollow(user.id)
                }
                .allowsHitTesting(store.people?.canFollow ?? true)
        }
        .padding(12)
        .frame(width: 138)
        .comicCard()
    }
}
