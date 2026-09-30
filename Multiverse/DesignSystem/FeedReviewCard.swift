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
                    .accessibilityLabel("\(review.rating.formatted()) de 5 estrelas")
                textBlock(hidden: hidden)
                posterButton
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    header(user: user, item: item, uni: uni)
                    StarsText(rating: review.rating, color: uni.color, size: 15)
                        .accessibilityLabel("\(review.rating.formatted()) de 5 estrelas")
                    textBlock(hidden: hidden)
                }
                Spacer(minLength: 6)
                posterButton
            }
        }
    }

    private func accessibilitySummary(user: User, item: Item) -> String {
        "Review de \(user.name), \(Logic.verb3(item.type)) \(item.title), nota \(review.rating.formatted()) de 5."
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
                .accessibilityLabel("Perfil de \(user.name)")
                if let badgeUni = store.universe(user.badgeUniverse), let badgeName = store.badgeNames[user.badgeUniverse] {
                    BadgeChip(label: badgeName, universe: badgeUni)
                }
                if showFollowingTag {
                    Text("SEGUINDO").font(MVFont.black(8)).tracking(0.4)
                        .foregroundStyle(MV.C.card)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: MV.R.xs).fill(MV.C.ink))
                }
                Spacer()
                Button { showReportSheet = true } label: {
                    Text("•••").font(MVFont.black(14)).foregroundStyle(MV.C.muted).padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mais opções")
            }
            HStack(spacing: 4) {
                Text(Logic.verb3(item.type)).font(MVFont.body(13, weight: 600)).foregroundStyle(MV.C.ink)
                Button { store.push(.item(item.id)) } label: {
                    Text(item.title).font(MVFont.body(13, weight: 700)).underline().foregroundStyle(MV.C.ink)
                        .lineLimit(isAccessibilitySize ? 2 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ver \(item.title)")
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
                    Text("SPOILER · TOQUE PARA VER")
                        .font(MVFont.black(9)).tracking(0.6)
                        .foregroundStyle(MV.C.card)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(MV.C.ink))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Contém spoiler. Toque pra revelar o texto.")
            }
        }
    }

    @ViewBuilder
    private func footer(review: Review) -> some View {
        let liked = store.isLikedReview(review.id)
        let likeButton = Text("♥ \(Logic.fmt(store.reviewLikeCount(review)))")
            .font(MVFont.bold(12))
            .padding(.horizontal, 11).padding(.vertical, 5)
            .foregroundStyle(liked ? MV.C.card : MV.C.ink)
            .background(Capsule().fill(liked ? MV.C.marvel : MV.C.card))
            .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .burstOnTap("POW!", color: MV.C.marvel, when: !liked) {
                store.toggleLikedReview(review.id)
            }
            .accessibilityLabel(liked ? "Descurtir" : "Curtir")
            .accessibilityValue("\(store.reviewLikeCount(review)) curtidas")
            .accessibilityAddTraits(.isButton)

        let commentButton = PillButton(title: store.commentsLabel(for: review)) { store.push(.review(review.id)) }
            .accessibilityLabel("Ver comentários, \(review.comments.count)")

        let timeLabel = Text(review.when).font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)

        VStack(spacing: 8) {
            Rectangle().fill(MV.C.divider).frame(height: 1.5)
            if isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    likeButton
                    commentButton
                    timeLabel
                }
            } else {
                HStack(spacing: 8) {
                    likeButton
                    commentButton
                    Spacer()
                    timeLabel
                }
            }
        }
    }
}
