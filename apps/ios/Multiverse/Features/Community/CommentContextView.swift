import SwiftUI

struct CommentMessage: View {
    let comment: RemoteComment
    @Binding var revealed: Set<String>

    var body: some View {
        if comment.spoiler && !revealed.contains(comment.id) {
            Button(L10n.text("REVELAR SPOILER")) { revealed.insert(comment.id) }
        } else {
            MentionedText(text: comment.text, mentions: comment.mentions ?? []).font(MVFont.body(14, weight: 500))
        }
    }
}

struct CommentContextView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var context: CommentContext
    @State private var revealed: Set<String> = []

    init(api: any CommunityAPI, post: String, target: String) {
        _context = State(initialValue: CommentContext(api: api, post: post, target: target))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScreenScaffold {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        Text(L10n.text("CONTEXTO DA CONVERSA")).font(MVFont.section(22))
                        if let error = context.error {
                            AuthErrorBanner(message: error)
                            Button(L10n.text("TENTAR DE NOVO")) { Task { await context.load(earlier: context.earlierID != nil) } }.disabled(context.busy)
                        }
                        if context.busy { ProgressView() }
                        if context.earlierID != nil {
                            Button(L10n.text("VER CONTEXTO ANTERIOR")) {
                                let anchor = context.comments.first?.id
                                Task {
                                    await context.load(earlier: true)
                                    if let anchor { proxy.scrollTo(anchor, anchor: .top) }
                                }
                            }.font(MVFont.bold(12)).disabled(context.busy)
                        } else if context.comments.first?.isReply == true {
                            Text(L10n.text("Um comentário anterior não está disponível.")).font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                        }
                        ForEach(context.comments) { comment in
                            VStack(alignment: .leading, spacing: 10) {
                                if comment.id == context.targetID {
                                    Text(L10n.text("RESPOSTA SELECIONADA")).font(MVFont.bold(10)).foregroundStyle(MV.C.muted)
                                }
                                if let user = context.users[comment.user] {
                                    Button {
                                        dismiss(); store.openUserProfile(user.id)
                                    } label: {
                                        HStack { AvatarView(user: user, size: 30); Text(user.name).font(MVFont.bold(13)) }
                                    }.buttonStyle(.plain)
                                }
                                CommentMessage(comment: comment, revealed: $revealed)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14).comicCard().id(comment.id)
                        }
                    }.foregroundStyle(MV.C.ink).padding(MV.pad)
                }.refreshable { await context.load() }
            }
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L10n.text("FECHAR")) { dismiss() }.foregroundStyle(MV.C.ink) }
            }
        }
        .presentationDragIndicator(.visible)
        .task { await context.load() }
    }
}
