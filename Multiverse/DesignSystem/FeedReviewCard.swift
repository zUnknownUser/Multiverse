import SwiftUI

/// Card de review usado no feed da Home, na Obra, no Universo e no Perfil.
struct FeedReviewCard: View {
    let review: Review
    var showFollowingTag = false

    @Environment(AppStore.self) private var store

    var body: some View {
        guard let user = store.user(review.user), let item = store.item(review.item) else {
            return AnyView(EmptyView())
        }
        let uni = store.universe(of: item)
        let hidden = store.isSpoilerHidden(review)
        let poster = Logic.posterColors(item: item, universe: uni)

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        header(user: user, item: item, uni: uni)
                        StarsText(rating: review.rating, color: uni.color, size: 15)
                        textBlock(hidden: hidden)
                    }
                    Spacer(minLength: 6)
                    Button { store.push(.item(item.id)) } label: {
                        ZStack {
                            poster.bg
                            Halftone()
                        }
                        .frame(width: 58, height: 87)
                        .comicCard(bg: poster.bg, radius: MV.R.md, shadow: MV.Shadow.s)
                    }
                    .buttonStyle(.plain)
                }
                footer(review: review)
            }
            .padding(12)
            .comicCard()
            .contentShape(Rectangle())
            .onTapGesture { if !hidden { store.push(.review(review.id)) } }
        )
    }

    @ViewBuilder
    private func header(user: User, item: Item, uni: Universe) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Button { store.openUserProfile(user.id) } label: { AvatarView(user: user, size: 28) }
                    .buttonStyle(.plain)
                Button { store.openUserProfile(user.id) } label: {
                    Text(user.name).font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                }
                .buttonStyle(.plain)
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
            }
            HStack(spacing: 4) {
                Text(Logic.verb3(item.type)).font(MVFont.body(13, weight: 600)).foregroundStyle(MV.C.ink)
                Button { store.push(.item(item.id)) } label: {
                    Text(item.title).font(MVFont.body(13, weight: 700)).underline().foregroundStyle(MV.C.ink)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
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
            }
        }
    }

    @ViewBuilder
    private func footer(review: Review) -> some View {
        let liked = store.isLikedReview(review.id)
        VStack(spacing: 8) {
            Rectangle().fill(MV.C.divider).frame(height: 1.5)
            HStack(spacing: 8) {
                Text("♥ \(Logic.fmt(store.reviewLikeCount(review)))")
                    .font(MVFont.bold(12))
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .foregroundStyle(liked ? MV.C.card : MV.C.ink)
                    .background(Capsule().fill(liked ? MV.C.marvel : MV.C.card))
                    .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .burstOnTap("POW!", color: MV.C.marvel, when: !liked) {
                        store.toggleLikedReview(review.id)
                    }
                PillButton(title: store.commentsLabel(for: review)) { store.push(.review(review.id)) }
                Spacer()
                Text(review.when).font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
            }
        }
    }
}
