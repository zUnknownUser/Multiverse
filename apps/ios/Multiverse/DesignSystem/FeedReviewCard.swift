import SwiftUI

/// Card de review usado no feed da Home, na Obra, no Universo e no Perfil.
/// Acessível: Texto Dinâmico (via `MVFont`, ver Theme.swift), VoiceOver e recolhe pra
/// coluna única em tamanhos grandes (ver `3a-acessibilidade.png`).
struct FeedReviewCard: View {
    let review: Review
    var showFollowingTag = false

    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showReportSheet = false
    @State private var showReactionBar = false

    private var isAccessibilitySize: Bool { dynamicTypeSize >= .accessibility1 }

    var body: some View {
        guard let user = store.user(review.user), let item = store.item(review.item) else {
            return AnyView(EmptyView())
        }
        if store.isShieldedReview(review) {
            return AnyView(ShieldedReviewCard(review: review))
        }
        let uni = store.universe(of: item)
        let hidden = store.isSpoilerHidden(review)
        let poster = Logic.posterColors(item: item, universe: uni)

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                content(user: user, item: item, uni: uni, poster: poster, hidden: hidden)
                footer(review: review)
            }
            .padding(12)
            .comicCard()
            .contentShape(Rectangle())
            .onTapGesture { if !hidden { store.push(.review(review.id)) } }
            .reactionBar(isPresented: $showReactionBar) { type in
                store.setReaction(type, for: review.id)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilitySummary(user: user, item: item))
            .sheet(isPresented: $showReportSheet) {
                ReportSheet(targetType: "review", targetID: review.id, authorHandle: user.handle, targetTitle: item.title)
            }
        )
    }

    @ViewBuilder
    private func content(user: User, item: Item, uni: Universe, poster: (bg: Color, fg: Color), hidden: Bool) -> some View {
        let posterButton = Button { store.push(.item(item.id)) } label: {
            ZStack { poster.bg; Halftone() }
                .frame(width: 58, height: 87)
                .comicCard(bg: poster.bg, radius: MV.R.md, shadow: MV.Shadow.s)
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)

        if isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                header(user: user, item: item, uni: uni)
                StarsText(rating: review.rating, color: uni.color, size: 15)
                    .accessibilityLabel(L10n.format("%1$@ de 5 estrelas", String(describing: review.rating.formatted())))
                textBlock(hidden: hidden)
                posterButton
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    header(user: user, item: item, uni: uni)
                    StarsText(rating: review.rating, color: uni.color, size: 15)
                        .accessibilityLabel(L10n.format("%1$@ de 5 estrelas", String(describing: review.rating.formatted())))
                    textBlock(hidden: hidden)
                }
                Spacer(minLength: 6)
                posterButton
            }
        }
    }

    private func accessibilitySummary(user: User, item: Item) -> String {
        L10n.format("Review de %1$@, %2$@ %3$@, nota %4$@ de 5.", String(describing: user.name), String(describing: Logic.verb3(item.type)), String(describing: item.title), String(describing: review.rating.formatted()))
    }

    @ViewBuilder
    private func header(user: User, item: Item, uni: Universe) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Button { store.openUserProfile(user.id) } label: { AvatarView(user: user, size: 28) }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                Button { store.openUserProfile(user.id) } label: {
                    Text(user.name).font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.format("Perfil de %1$@", String(describing: user.name)))
                if let badgeUni = store.universe(user.badgeUniverse), let badgeName = store.badgeNames[user.badgeUniverse] {
                    BadgeChip(label: badgeName, universe: badgeUni)
                }
                if showFollowingTag {
                    Text(L10n.text("SEGUINDO")).font(MVFont.black(8)).tracking(0.4)
                        .foregroundStyle(MV.C.card)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: MV.R.xs).fill(MV.C.ink))
                }
                Spacer()
                if !store.isRemoteReview(review.id) || review.user != store.meID {
                    Button { showReportSheet = true } label: {
                        Text("•••").font(MVFont.black(14)).foregroundStyle(MV.C.muted).padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("Mais opções"))
                }
            }
            HStack(spacing: 4) {
                Text(Logic.verb3(item.type)).font(MVFont.body(13, weight: 600)).foregroundStyle(MV.C.ink)
                Button { store.push(.item(item.id)) } label: {
                    Text(item.title).font(MVFont.body(13, weight: 700)).underline().foregroundStyle(MV.C.ink)
                        .lineLimit(isAccessibilitySize ? 2 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.format("Ver %1$@", String(describing: item.title)))
            }
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheet(targetType: "review", targetID: review.id, authorHandle: user.handle, targetTitle: item.title)
        }
    }

    @ViewBuilder
    private func textBlock(hidden: Bool) -> some View {
        ZStack {
            Text(review.text)
                .font(MVFont.body(13, weight: 500))
                .lineSpacing(4)
                .foregroundStyle(MV.C.ink)
                .blur(radius: hidden ? 6 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(hidden)
            if hidden {
                Button {
                    store.revealSpoiler(review.id)
                } label: {
                    Text(L10n.text("SPOILER · TOQUE PARA VER"))
                        .font(MVFont.black(9)).tracking(0.6)
                        .foregroundStyle(MV.C.card)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(MV.C.ink))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("Contém spoiler. Toque pra revelar o texto."))
            }
        }
    }

    @ViewBuilder
    private func footer(review: Review) -> some View {
        let reactions = ReactionPillsRow(reviewID: review.id)
            .accessibilityLabel(reactionsAccessibilityLabel(review))

        let commentButton = PillButton(title: store.commentsLabel(for: review)) { store.push(.review(review.id)) }
            .accessibilityLabel(store.commentsLabel(for: review))

        let timeLabel = Text(review.when).font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)

        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(MV.C.divider).frame(height: 1.5)
            reactions
            if isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    commentButton
                    timeLabel
                }
            } else {
                HStack(spacing: 8) {
                    commentButton
                    Spacer()
                    timeLabel
                }
            }
        }
    }

    private func reactionsAccessibilityLabel(_ review: Review) -> String {
        let counts = store.reactionCounts(for: review.id)
        guard !counts.isEmpty else { return L10n.text("Segure pra reagir") }
        return L10n.text("Reações: ") + counts.map { "\($0.type.subtitle.capitalized) \($0.count)" }.joined(separator: ", ")
    }
}
