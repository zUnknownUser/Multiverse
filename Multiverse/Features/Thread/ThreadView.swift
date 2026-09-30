import SwiftUI

struct ThreadView: View {
    let reviewID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            if let review = store.review(reviewID), let item = store.item(review.item) {
                let uni = store.universe(of: item)
                VStack(alignment: .leading, spacing: 18) {
                    miniHeader(item: item, uni: uni)
                    ReviewDetailCard(review: review)
                    commentsSection(review: review)
                }
                .padding(.horizontal, MV.pad)
                .padding(.bottom, 90)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let review = store.review(reviewID) {
                replyBar(review: review)
            }
        }
    }

    @ViewBuilder
    private func miniHeader(item: Item, uni: Universe) -> some View {
        Button { store.push(.item(item.id)) } label: {
            HStack(spacing: 10) {
                let p = Logic.posterColors(item: item, universe: uni)
                ZStack { p.bg; Halftone() }
                    .frame(width: 44, height: 66)
                    .comicCard(bg: p.bg, radius: MV.R.sm, shadow: MV.Shadow.s)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(uni.name) · \(item.type)").font(MVFont.body(11, weight: 700)).foregroundStyle(MV.C.muted)
                    Text(item.title).font(MVFont.bold(16)).foregroundStyle(MV.C.ink)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func commentsSection(review: Review) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(review.comments.isEmpty ? "SEM COMENTÁRIOS AINDA" : "\(review.comments.count) COMENTÁRIOS")
                .font(MVFont.section(16)).foregroundStyle(MV.C.ink)
            VStack(spacing: 12) {
                ForEach(Array(review.comments.enumerated()), id: \.offset) { index, comment in
                    CommentRow(review: review, comment: comment, index: index)
                }
            }
        }
    }

    @ViewBuilder
    private func replyBar(review: Review) -> some View {
        let me = store.user(store.meID)!
        HStack(spacing: 8) {
            AvatarView(user: me, size: 34)
            TextField("Responder… (teorias bem-vindas)", text: $draft)
                .font(MVFont.body(14, weight: 500))
                .focused($focused)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(MV.C.card)
                .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(Capsule())
                .onSubmit { send(review: review) }
            Text("ENVIAR")
                .font(MVFont.bold(12))
                .padding(.horizontal, 14)
                .frame(height: 42)
                .foregroundStyle(MV.C.paper)
                .background(MV.C.ink)
                .clipShape(Capsule())
                .contentShape(Rectangle())
                .onTapGesture { send(review: review) }
        }
        .padding(.horizontal, MV.pad)
        .padding(.vertical, 10)
        .background(MV.C.paper)
        .overlay(alignment: .top) { Rectangle().fill(MV.C.ink).frame(height: MV.stroke) }
    }

    private func send(review: Review) {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.postComment(reviewID: review.id, text: draft)
        draft = ""
    }
}

private struct ReviewDetailCard: View {
    let review: Review
    @Environment(AppStore.self) private var store

    var body: some View {
        guard let user = store.user(review.user) else { return AnyView(EmptyView()) }
        let item = store.item(review.item)
        let uni = item.map { store.universe(of: $0) }
        let hidden = store.isSpoilerHidden(review)

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    AvatarView(user: user, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(user.name).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                            if let badgeUni = store.universe(user.badgeUniverse), let badge = store.badgeNames[user.badgeUniverse] {
                                BadgeChip(label: badge, universe: badgeUni)
                            }
                        }
                        Text(review.when).font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                    }
                    Spacer()
                    StarsText(rating: review.rating, color: uni?.color ?? MV.C.ink, size: 17)
                }

                ZStack {
                    Text(review.text)
                        .font(MVFont.body(15, weight: 500))
                        .lineSpacing(5)
                        .foregroundStyle(MV.C.ink)
                        .blur(radius: hidden ? 6 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if hidden {
                        Button { store.revealSpoiler(review.id) } label: {
                            Text("SPOILER · TOQUE PARA VER")
                                .font(MVFont.black(10)).tracking(0.6)
                                .foregroundStyle(MV.C.card)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(MV.C.ink))
                        }
                        .buttonStyle(.plain)
                    }
                }

                let liked = store.isLikedReview(review.id)
                Text("♥ \(Logic.fmt(store.reviewLikeCount(review))) curtidas")
                    .font(MVFont.bold(12))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .foregroundStyle(liked ? MV.C.card : MV.C.ink)
                    .background(liked ? MV.C.marvel : MV.C.card)
                    .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(Capsule())
                    .burstOnTap("POW!", color: MV.C.marvel, when: !liked) {
                        store.toggleLikedReview(review.id)
                    }
            }
            .padding(14)
            .comicCard(shadow: MV.Shadow.l)
        )
    }
}

private struct CommentRow: View {
    let review: Review
    let comment: Comment
    let index: Int
    @Environment(AppStore.self) private var store

    var body: some View {
        guard let user = store.user(comment.user) else { return AnyView(EmptyView()) }
        let liked = store.isLikedComment(reviewID: review.id, index: index)

        return AnyView(
            HStack(alignment: .top, spacing: 8) {
                Button { store.openUserProfile(user.id) } label: { AvatarView(user: user, size: 30) }
                    .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(user.name).font(MVFont.bold(12)).foregroundStyle(MV.C.ink)
                        Text(comment.when ?? "agora").font(MVFont.body(10, weight: 600)).foregroundStyle(MV.C.muted)
                    }
                    Text(comment.text).font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.ink)
                }
                .padding(10)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 12)
                        .fill(MV.C.card)
                )
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 12)
                        .strokeBorder(MV.C.ink, lineWidth: MV.stroke)
                )

                Spacer(minLength: 0)

                Text("♥ \(Logic.fmt(store.commentLikeCount(review: review, index: index)))")
                    .font(MVFont.bold(11))
                    .foregroundStyle(liked ? MV.C.marvel : MV.C.ink)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.toggleLikedComment(reviewID: review.id, index: index)
                    }
            }
        )
    }
}
