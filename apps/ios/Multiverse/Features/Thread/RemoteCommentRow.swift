import SwiftUI

struct RemoteCommentRow: View {
    let reviewID: String
    let comment: RemoteComment
    let onReply: () -> Void
    @Environment(AppStore.self) private var store
    @State private var showReactions = false
    @State private var showReport = false
    @State private var revealed = false

    var body: some View {
        if let user = store.social?.users[comment.user] {
            let hidden = comment.spoiler && !revealed
            HStack(alignment: .top, spacing: 8) {
                Button { store.openUserProfile(user.id) } label: { AvatarView(user: user, size: 30) }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(user.name).font(MVFont.bold(12))
                        Text(L10n.date(comment.createdAt, template: "d MMM HH:mm")).font(MVFont.body(10)).foregroundStyle(MV.C.muted)
                        Spacer()
                        if comment.user != store.meID {
                            Button { showReport = true } label: { Text("•••").font(MVFont.bold(14)) }
                                .buttonStyle(.plain).accessibilityLabel(L10n.text("Mais opções"))
                        }
                    }
                    if hidden {
                        Button { revealed = true } label: {
                            Text(L10n.text("SPOILER · TOQUE PARA VER")).font(MVFont.bold(11)).padding(.vertical, 8)
                        }.buttonStyle(.plain)
                    } else {
                        Text(comment.text).font(MVFont.body(13, weight: 500))
                    }
                    ReactionPillsRow(reviewID: comment.id)
                }
                .foregroundStyle(MV.C.ink)
                .padding(10)
                .background(MV.C.card)
                .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .reactionBar(isPresented: $showReactions, onReact: { store.setReaction($0, for: comment.id) }, onQuote: onReply, quoteLabel: L10n.text("Responder"))
                Button {
                    guard let social = store.social else { return }
                    Task {
                        let current = social.interactions[comment.id]
                        if !(await social.setReaction(reviewID: reviewID, commentID: comment.id, reaction: current?.myReaction, liked: !(current?.liked ?? false))), let error = social.actionError { store.showToast(error) }
                    }
                } label: {
                    Text("♥ \(store.social?.interactions[comment.id]?.likes ?? 0)").font(MVFont.bold(11))
                        .foregroundStyle(store.social?.interactions[comment.id]?.liked == true ? MV.C.marvel : MV.C.ink)
                }
                .buttonStyle(.plain).disabled(store.social?.reacting.contains(comment.id) == true)
            }
            .sheet(isPresented: $showReport) {
                ReportSheet(targetType: "comentário", targetID: comment.id, authorHandle: user.handle,
                            targetTitle: store.review(reviewID).flatMap { store.item($0.item)?.title } ?? "", reviewID: reviewID)
            }
        }
    }
}
