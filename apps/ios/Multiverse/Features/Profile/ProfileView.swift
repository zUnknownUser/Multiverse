import SwiftUI

struct ProfileView: View {
    let userID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let isRoot = store.tab == .profile && userID == store.meID && store.profilePath.isEmpty
        ScreenScaffold(showBack: !isRoot, onBack: { dismiss() }) {
            if let people = store.people, userID != store.meID, let error = people.profileErrors[userID] {
                PeopleStatusNotice(message: error) { await people.loadProfile(userID) }.padding(MV.pad)
            } else if store.user(userID) == nil || (store.usesRemotePeople && userID != store.meID && store.people?.profiles[userID] == nil) {
                ProgressView().frame(maxWidth: .infinity).padding(MV.pad)
            } else {
                let data = store.profileData(for: userID)
                VStack(alignment: .leading, spacing: 22) {
                    if data.isMe { ActivityRefreshNotice().padding(.horizontal, MV.pad) }
                    if let error = store.people?.homeError, data.isMe {
                        PeopleStatusNotice(message: error) { await store.people?.loadHome() }.padding(.horizontal, MV.pad)
                    }
                    if let error = store.people?.followError { AuthErrorBanner(message: error).padding(.horizontal, MV.pad) }
                    hero(data: data)
                        .padding(.horizontal, MV.pad)

                    if data.isMe && store.showsDemoFeatures {
                        WrappedPromoCard()
                            .padding(.horizontal, MV.pad)
                    } else if let compat = data.compatPercent, let line = data.compatLine, let byUni = data.compatByUniverse {
                        AffinityCard(percent: compat, line: line, byUniverse: byUni, agree: data.agreeLine ?? "", disagree: data.disagreeLine ?? "")
                            .padding(.horizontal, MV.pad)
                    }

                    if !data.progress.isEmpty { canonSection(data: data).padding(.horizontal, MV.pad) }
                    if store.showsDemoFeatures && !data.badges.isEmpty { badgesSection(data: data).padding(.horizontal, MV.pad) }
                    favoritesSection(data: data).padding(.horizontal, MV.pad)
                    reviewsSection(data: data).padding(.horizontal, MV.pad)

                    if data.isMe {
                        if store.showsDemoFeatures { clubsSection().padding(.horizontal, MV.pad) }
                        listsSection().padding(.horizontal, MV.pad)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .task(id: userID + "|" + String(store.people?.discoveryEpoch ?? 0)) { await refreshPeople() }
        .refreshable {
            if userID == store.meID { await store.refreshActivity() }
            await refreshPeople()
        }
    }

    private func refreshPeople() async {
        if userID == store.meID { await store.people?.loadHome(); await store.library?.refresh() }
        else { await store.people?.loadProfile(userID) }
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
                } else if let social = store.social {
                    Menu {
                        Button(L10n.text("BLOQUEAR"), role: .destructive) {
                            Task {
                                if await social.setBlock(userID, blocked: true) { await store.refreshAfterSafetyChange() }
                                else { store.showToast(social.actionError ?? SocialError.invalid.localizedDescription) }
                            }
                        }
                    } label: {
                        Text("•••").font(MVFont.black(16)).foregroundStyle(MV.C.paper).padding(8)
                    }
                    .accessibilityLabel(L10n.text("Mais opções"))
                    .disabled(social.isMutating)
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
                        Text(L10n.text("DIÁRIO")).font(MVFont.bold(12)).foregroundStyle(MV.C.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(MV.C.paper)
                            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    }
                    .buttonStyle(.plain)
                    Button { store.openLogBlank() } label: {
                        Text(L10n.text("+ REGISTRAR")).font(MVFont.bold(12)).foregroundStyle(MV.C.paper)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(MV.C.marvel)
                            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.paper, lineWidth: MV.stroke))
                            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                let following = store.isFollowing(userID)
                HStack(spacing: 10) {
                    Text(store.people?.savingPersonID == userID ? L10n.text("SALVANDO…") : (following ? L10n.text("SEGUINDO") : L10n.text("SEGUIR")))
                        .font(MVFont.bold(13))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(following ? MV.C.paper : MV.C.ink)
                        .background(following ? Color.clear : MV.C.paper)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.paper, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                        .burstOnTap("ZAP!", color: MV.C.dc, when: !following && !store.usesRemotePeople) {
                            store.toggleFollow(userID)
                        }
                        .allowsHitTesting(store.people?.canFollow ?? true)
                    if store.showsDemoFeatures {
                    Text(L10n.text("MENSAGEM"))
                        .font(MVFont.bold(13))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(MV.C.paper)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.paper, lineWidth: MV.stroke))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if store.usesRemotePeople { store.showToast(L10n.text("Mensagens entre loristas estarão disponíveis em breve.")) }
                            else { store.push(.conversation(userID)) }
                        }
                    Text(L10n.text("DESAFIAR"))
                        .font(MVFont.bold(13))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(MV.C.ink)
                        .background(MV.C.wow)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.paper, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if store.usesRemotePeople { store.showToast(L10n.text("Desafios entre loristas estarão disponíveis em breve.")) }
                            else { store.showingChallengeUserID = userID }
                        }
                    }
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
            Text(L10n.text("CÂNONE CONSUMIDO")).font(MVFont.section(17)).foregroundStyle(MV.C.ink)
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
            Text(L10n.text("SELOS")).font(MVFont.section(17)).foregroundStyle(MV.C.ink)
            HStack(spacing: 10) {
                ForEach(data.badges, id: \.universe.id) { badge in
                    BadgeDiamond(badge: badge)
                }
            }
        }
    }

    @ViewBuilder
    private func favoritesSection(data: AppStore.ProfileData) -> some View {
        if !data.favorites.isEmpty || (data.isMe && store.usesRemoteActivity) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("FAVORITOS")).font(MVFont.section(17)).foregroundStyle(MV.C.ink)
                if data.favorites.isEmpty {
                    Text(L10n.text(store.library == nil ? "Os registros marcados com ♥ Curti aparecerão aqui." : "Marque o coração de uma obra para adicioná-la aos favoritos."))
                        .font(MVFont.body(13)).foregroundStyle(MV.C.muted)
                }
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
        if !data.recentReviews.isEmpty || (data.isMe && store.usesRemoteActivity) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("REVIEWS RECENTES")).font(MVFont.section(17)).foregroundStyle(MV.C.ink)
                if data.recentReviews.isEmpty {
                    Text(L10n.text("Suas notas e reviews aparecerão aqui após o primeiro registro."))
                        .font(MVFont.body(13)).foregroundStyle(MV.C.muted)
                }
                VStack(spacing: 10) {
                    ForEach(data.recentReviews) { review in
                        CompactReviewRow(review: review)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func clubsSection() -> some View {
        if !store.clubs.isEmpty { MyClubsCard() }
    }

    @ViewBuilder
    private func listsSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.text("LISTAS")).font(MVFont.section(17))
                Spacer()
                if store.library != nil { Button(L10n.text("ABRIR BIBLIOTECA")) { store.goToTab(.library) }.font(MVFont.bold(11)) }
            }
            if let library = store.library {
                LibraryStatusNotice(library: library)
                if library.lists.isEmpty && library.snapshot != nil { Text(L10n.text("Crie sua primeira lista para organizar as obras.")).font(MVFont.body(13)) }
                ForEach(library.lists.prefix(3)) { list in PersonalListRow(list: list) }
            } else if store.showsDemoFeatures {
                ForEach(store.profileLists(), id: \.list.id) { entry in ListSummaryRow(list: entry.list, stackColors: entry.stackColors) }
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
            Text(badge.achieved ? L10n.text("Conquistado") : L10n.format("faltam %1$@%%", String(describing: badge.remainingPct)))
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
                    Text(L10n.format("♥ %1$@ · %2$@ comentários", String(describing: Logic.fmt(store.reviewLikeCount(review))), String(describing: review.comments.count)))
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
                Text(L10n.format("%1$@ itens · ♥ %2$@ · %3$@ comentários", String(describing: list.items.count), String(describing: Logic.fmt(store.listLikeCount(list))), String(describing: list.comments)))
                    .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { store.push(.list(list.id)) }
    }
}
