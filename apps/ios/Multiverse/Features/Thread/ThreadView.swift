import SwiftUI
import UIKit

struct ThreadView: View {
    let reviewID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var quoting: (author: String, text: String)?
    @FocusState private var focused: Bool
    @State private var validated = false
    @State private var commentSpoiler = false
    @State private var pendingComment: (id: String, text: String, spoiler: Bool)?

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            if store.isRemoteReview(reviewID), let social = store.social, let error = social.detailErrors[reviewID] {
                PeopleStatusNotice(message: error) { await social.loadReview(reviewID) }.padding(MV.pad)
            } else if store.isRemoteReview(reviewID) && (!validated || store.social?.loadingDetails.contains(reviewID) == true) {
                ProgressView().frame(maxWidth: .infinity).padding(MV.pad)
            } else if let review = store.review(reviewID), let item = store.item(review.item) {
                let uni = store.universe(of: item)
                VStack(alignment: .leading, spacing: 18) {
                    miniHeader(item: item, uni: uni)
                    if store.isShieldedReview(review) {
                        ShieldedReviewCard(review: review)
                    } else {
                        ReviewDetailCard(review: review, onQuote: { quote(author: store.user(review.user)?.name ?? "", text: review.text) })
                        commentsSection(review: review)
                    }
                }
                .padding(.horizontal, MV.pad)
                .padding(.bottom, 90)
            } else if store.isRemoteReview(reviewID), let social = store.social {
                PeopleStatusNotice(message: SocialError.unavailable.localizedDescription) { await social.loadReview(reviewID) }.padding(MV.pad)
            }
        }
        .task(id: reviewID) {
            validated = false
            if store.isRemoteReview(reviewID) { await store.social?.loadReview(reviewID); await store.social?.loadComments(reviewID) }
            validated = true
        }
        .refreshable {
            if store.isRemoteReview(reviewID) { await store.social?.loadReview(reviewID); await store.social?.loadComments(reviewID) }
        }
        .safeAreaInset(edge: .bottom) {
            if let review = store.review(reviewID), !store.isRemoteReview(reviewID) || (validated && store.social?.detailErrors[reviewID] == nil) {
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
                    Text("\(uni.name) · \(L10n.text(item.type))").font(MVFont.body(11, weight: 700)).foregroundStyle(MV.C.muted)
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
            if store.isRemoteReview(reviewID), let social = store.social {
                Text(store.commentsLabel(for: review).uppercased()).font(MVFont.section(16)).foregroundStyle(MV.C.ink)
                if let error = social.commentErrors[reviewID] {
                    PeopleStatusNotice(message: error) { await social.loadComments(reviewID) }
                }
                if social.loadingComments.contains(reviewID) { ProgressView().frame(maxWidth: .infinity) }
                if !store.isSpoilerHidden(review) {
                    ForEach(social.comments[reviewID] ?? []) { comment in
                        RemoteCommentRow(reviewID: reviewID, comment: comment, onReply: {
                            guard pendingComment == nil else { return }
                            draft = (social.users[comment.user]?.handle ?? "") + " "
                            focused = true
                        })
                    }
                    if social.commentCursors[reviewID] != nil {
                        PrimaryAuthButton(title: L10n.text("VER MAIS")) { Task { await social.loadComments(reviewID, more: true) } }
                            .disabled(social.loadingComments.contains(reviewID))
                    }
                }
            } else {
                Text(review.comments.isEmpty ? L10n.text("SEM COMENTÁRIOS AINDA") : L10n.format("comments.uppercase", review.comments.count))
                    .font(MVFont.section(16)).foregroundStyle(MV.C.ink)
                VStack(spacing: 12) {
                    ForEach(Array(review.comments.enumerated()), id: \.offset) { index, comment in
                        CommentRow(review: review, comment: comment, index: index, onQuote: { quote(author: store.user(comment.user)?.name ?? "", text: comment.text) })
                    }
                }
            }
        }
    }

    private func quote(author: String, text: String) {
        if store.isRemoteReview(reviewID) {
            guard pendingComment == nil else { return }
            draft = (store.review(reviewID).flatMap { store.user($0.user)?.handle } ?? author) + " "
            focused = true
            return
        }
        quoting = (author, text)
        focused = true
    }

    @ViewBuilder
    private func replyBar(review: Review) -> some View {
        let me = store.user(store.meID)!
        VStack(spacing: 8) {
            if let quoting {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle().fill(MV.C.wow).frame(width: 3)
                    (Text(L10n.format("CITANDO %1$@: ", String(describing: quoting.author.uppercased()))).font(MVFont.black(11))
                        + Text("\"\(quoting.text)\"").font(MVFont.body(12, weight: 600)).italic())
                        .foregroundStyle(MV.C.ink)
                        .lineLimit(2)
                    Spacer()
                    Button { self.quoting = nil } label: {
                        Text("✕").font(.system(size: 13, weight: .bold)).foregroundStyle(MV.C.muted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(MV.C.wow.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.wow, lineWidth: MV.stroke))
                .padding(.horizontal, MV.pad)
            }
            if store.isRemoteReview(reviewID) {
                if pendingComment != nil && store.social?.sendingComments.contains(reviewID) != true && store.social?.commentErrors[reviewID] != nil {
                    Text(L10n.text("Envio pendente. Toque em ENVIAR para tentar novamente sem duplicar."))
                        .font(MVFont.body(12)).foregroundStyle(MV.C.muted).padding(.horizontal, MV.pad)
                }
                if store.social?.canComment[reviewID] == false {
                    Text(L10n.text("O autor limitou quem pode comentar.")).font(MVFont.body(12)).foregroundStyle(MV.C.muted).padding(.horizontal, MV.pad)
                }
                Toggle(L10n.text("Contém spoiler"), isOn: $commentSpoiler)
                    .font(MVFont.body(12)).tint(MV.C.marvel).padding(.horizontal, MV.pad)
                    .disabled(pendingComment != nil)
            }
            HStack(spacing: 8) {
                AvatarView(user: me, size: 34)
                TextField(L10n.text("Responder… (teorias bem-vindas)"), text: $draft)
                    .font(MVFont.body(14, weight: 500))
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(MV.C.card)
                    .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(Capsule())
                    .onSubmit { send(review: review) }
                    .disabled(store.isRemoteReview(reviewID) && (pendingComment != nil || store.social?.canComment[reviewID] != true))
                Text(L10n.text(store.social?.sendingComments.contains(reviewID) == true ? "SALVANDO…" : "ENVIAR"))
                    .font(MVFont.bold(12))
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .foregroundStyle(MV.C.paper)
                    .background(MV.C.ink)
                    .clipShape(Capsule())
                    .contentShape(Rectangle())
                    .onTapGesture { send(review: review) }
                    .allowsHitTesting(store.social?.sendingComments.contains(reviewID) != true)
            }
            .padding(.horizontal, MV.pad)
        }
        .padding(.vertical, 10)
        .background(MV.C.paper)
        .overlay(alignment: .top) { Rectangle().fill(MV.C.ink).frame(height: MV.stroke) }
    }

    private func send(review: Review) {
        if store.isRemoteReview(reviewID), let social = store.social {
            guard !social.sendingComments.contains(reviewID), social.canComment[reviewID] == true else { return }
            if pendingComment == nil {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                guard text.unicodeScalars.count <= 2000 else { store.showToast(L10n.text("O comentário pode ter até 2.000 caracteres.")); return }
                pendingComment = (UUID().uuidString.lowercased(), text, commentSpoiler)
            }
            guard let pending = pendingComment else { return }
            Task {
                if await social.postComment(reviewID: reviewID, id: pending.id, text: pending.text, spoiler: pending.spoiler) {
                    draft = ""; pendingComment = nil; commentSpoiler = false; quoting = nil
                    store.showToast(L10n.text("Comentário enviado."))
                }
            }
            return
        }
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.postComment(reviewID: review.id, text: draft, quote: quoting)
        draft = ""
        quoting = nil
    }
}

private struct ReviewDetailCard: View {
    let review: Review
    let onQuote: () -> Void
    @Environment(AppStore.self) private var store
    @State private var showReactionBar = false
    @State private var showingSend = false

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
                        if let item, uni != nil {
                            Text(L10n.format("sobre %1$@ · %2$@", String(describing: item.title), String(describing: review.when))).font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                        } else {
                            Text(review.when).font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                        }
                    }
                    Spacer()
                    StarsText(rating: review.rating, color: uni?.color ?? MV.C.ink, size: 17)
                }

                if !hidden {
                    HStack(spacing: 0) {
                        Text(L10n.text(store.isRemoteReview(review.id) ? "Responder" : "❝ Citar")).font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(MV.C.wow)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onQuote)
                        Text(L10n.text("Copiar")).font(MVFont.bold(13)).foregroundStyle(MV.C.paper)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(MV.C.ink)
                            .contentShape(Rectangle())
                            .onTapGesture { UIPasteboard.general.string = review.text }
                        Text("POW!").font(MVFont.bold(13)).foregroundStyle(MV.C.paper)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(MV.C.ink)
                            .burstOnTap("POW!", color: MV.C.marvel, when: !store.isRemoteReview(review.id) && store.userReaction(for: review.id) != .pow) {
                                store.setReaction(.pow, for: review.id)
                            }
                        if item != nil && store.showsDemoFeatures {
                            Text(L10n.text("Mandar")).font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(MV.C.card)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if store.isRemoteReview(review.id) { store.showToast(L10n.text("Mensagens entre loristas estarão disponíveis em breve.")) }
                                    else { showingSend = true }
                                }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .fixedSize()
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
                            Text(L10n.text("SPOILER · TOQUE PARA VER"))
                                .font(MVFont.black(10)).tracking(0.6)
                                .foregroundStyle(MV.C.card)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(MV.C.ink))
                        }
                        .buttonStyle(.plain)
                    }
                }

                ReactionPillsRow(reviewID: review.id)
            }
            .padding(14)
            .comicCard(shadow: MV.Shadow.l)
            .reactionBar(isPresented: $showReactionBar, onReact: { store.setReaction($0, for: review.id) }, onQuote: onQuote, quoteLabel: store.isRemoteReview(review.id) ? L10n.text("Responder") : nil)
            .sheet(isPresented: $showingSend) {
                if let item { SendCardSheet(itemID: item.id) }
            }
        )
    }
}

private struct CommentRow: View {
    let review: Review
    let comment: Comment
    let index: Int
    let onQuote: () -> Void
    @Environment(AppStore.self) private var store
    @State private var showReactionBar = false

    var body: some View {
        guard let user = store.user(comment.user) else { return AnyView(EmptyView()) }

        return AnyView(
            HStack(alignment: .top, spacing: 8) {
                Button { store.openUserProfile(user.id) } label: { AvatarView(user: user, size: 30) }
                    .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(user.name).font(MVFont.bold(12)).foregroundStyle(MV.C.ink)
                        Text(comment.when ?? L10n.text("agora")).font(MVFont.body(10, weight: 600)).foregroundStyle(MV.C.muted)
                    }
                    if let quotedAuthor = comment.quotedAuthor, let quotedText = comment.quotedText {
                        (Text("\(quotedAuthor.uppercased()): ").font(MVFont.black(10))
                            + Text("\"\(quotedText)\"").font(MVFont.body(11, weight: 600)).italic())
                            .foregroundStyle(MV.C.muted)
                            .padding(8)
                            .background(Color(hex: "#F3EDE0"))
                            .overlay(Rectangle().fill(MV.C.ink).frame(width: 2), alignment: .leading)
                            .lineLimit(2)
                    }
                    Text(comment.text).font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.ink)
                    ReactionPillsRow(reviewID: "\(review.id):c\(index)")
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
                .reactionBar(isPresented: $showReactionBar, onReact: { store.setReaction($0, for: "\(review.id):c\(index)") }, onQuote: onQuote)

                Spacer(minLength: 0)

                let liked = store.isLikedComment(reviewID: review.id, index: index)
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
