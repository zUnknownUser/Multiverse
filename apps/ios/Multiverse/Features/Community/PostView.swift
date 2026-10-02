import SwiftUI

struct PostView: View {
    let id: String
    @Environment(AppStore.self) private var store
    @State private var thread: CommunityThread?
    var body: some View {
        Group {
            if let thread { PostThreadView(thread: thread) } else { ProgressView() }
        }.task(id: id) {
            if thread == nil, let api = store.communityAPI { thread = CommunityThread(api: api, id: id) }
        }
    }
}
private struct PostThreadView: View {
    let thread: CommunityThread
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var revealed: Set<String> = []
    @State private var text = ""
    @State private var spoiler = false
    @State private var pending: (id: String, text: String, spoiler: Bool)?
    @State private var reportTarget: ReportTarget?
    @State private var deleting = false
    private struct ReportTarget: Identifiable { let id: String; let comment: String?; let author: String }
    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 18) {
                if let error = thread.error { AuthErrorBanner(message: error); Button(L10n.text("TENTAR DE NOVO")) { Task { await thread.load() } } }
                if thread.busy { ProgressView() }
                if let post = thread.post {
                    VStack(alignment: .leading, spacing: 14) {
                        author(post.user)
                        HStack {
                            Button(store.universe(post.universeID)?.name ?? post.universeID) { store.push(.community(universe: post.universeID, item: nil)) }
                            if let item = post.itemID { Button(store.item(item)?.title ?? item) { store.push(.item(item)) } }
                        }.font(MVFont.body(12, weight: 700))
                        if post.spoiler && !revealed.contains(post.id) {
                            Button(L10n.text("REVELAR SPOILER")) { revealed.insert(post.id) }
                        } else {
                            Text(post.title).font(MVFont.section(22))
                            Text(post.text).font(MVFont.body(15, weight: 500)).textSelection(.enabled)
                        }
                        reactions(comment: nil)
                        if post.user == store.meID {
                            Button(L10n.text("EXCLUIR PUBLICAÇÃO"), role: .destructive) { deleting = true }
                        } else {
                            Button(L10n.text("DENUNCIAR")) { reportTarget = .init(id: post.id, comment: nil, author: post.user) }
                        }
                    }.padding(14).comicCard()
                    Text(L10n.text("COMENTÁRIOS")).font(MVFont.section(18))
                    ForEach(thread.comments) { comment in
                        VStack(alignment: .leading, spacing: 10) {
                            author(comment.user)
                            if comment.spoiler && !revealed.contains(comment.id) {
                                Button(L10n.text("REVELAR SPOILER")) { revealed.insert(comment.id) }
                            } else { Text(comment.text).font(MVFont.body(14, weight: 500)).textSelection(.enabled) }
                            reactions(comment: comment.id)
                            if comment.user != store.meID {
                                Button(L10n.text("DENUNCIAR")) { reportTarget = .init(id: comment.id, comment: comment.id, author: comment.user) }.font(MVFont.body(11, weight: 700))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).comicCard()
                    }
                    if thread.cursor != nil { Button(L10n.text("CARREGAR MAIS")) { Task { await thread.load(more: true) } }.disabled(thread.busy) }
                    if thread.canComment {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField(L10n.text("Escreva um comentário"), text: $text, axis: .vertical).lineLimit(3...8).disabled(thread.busy || pending != nil)
                            Toggle(L10n.text("Contém spoiler"), isOn: $spoiler).disabled(thread.busy || pending != nil)
                            if pending != nil { Text(L10n.text("Envio pendente. Tente novamente para confirmar sem duplicar sua publicação.")).font(.caption) }
                            Button(L10n.text("ENVIAR")) { Task { await reply() } }.disabled(thread.busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.unicodeScalars.count > 2000)
                        }.padding(14).comicCard()
                    } else { Text(L10n.text("O autor limitou quem pode comentar.")) }
                }
            }.foregroundStyle(MV.C.ink).padding(MV.pad)
        }.task { await thread.load() }.refreshable { await thread.load() }
        .confirmationDialog(L10n.text("Excluir esta publicação?"), isPresented: $deleting, titleVisibility: .visible) {
            Button(L10n.text("EXCLUIR PUBLICAÇÃO"), role: .destructive) { Task { if await thread.delete() { dismiss() } } }
        }
        .sheet(item: $reportTarget) { target in
            CommunityReportForm(thread: thread, comment: target.comment, author: target.author) {
                reportTarget = nil
                store.social?.invalidateFeed()
                Task { await store.notifications?.refresh() }
                if target.comment == nil || thread.post == nil { dismiss() }
            }
        }
    }
    @ViewBuilder private func author(_ id: String) -> some View {
        if let user = thread.users[id] {
            Button { store.openUserProfile(id) } label: { HStack { AvatarView(user: user, size: 30); Text(user.name).font(MVFont.bold(13)) } }.buttonStyle(.plain)
        }
    }
    @ViewBuilder private func reactions(comment: String?) -> some View {
        if let summary = thread.interactions[comment ?? thread.id] {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button { Task { await thread.react(comment: comment, reaction: summary.myReaction, liked: !summary.liked) } } label: {
                        Label("\(summary.likes)", systemImage: summary.liked ? "heart.fill" : "heart")
                    }
                    ForEach(ReactionType.allCases, id: \.self) { type in
                        Button { Task { await thread.react(comment: comment, reaction: summary.myReaction == type.rawValue ? nil : type.rawValue, liked: summary.liked) } } label: {
                            Text("\(type.rawValue) \(summary.reactions[type.rawValue] ?? 0)").underline(summary.myReaction == type.rawValue)
                        }
                    }
                }.font(MVFont.bold(12)).disabled(thread.busy)
            }
        }
    }
    private func reply() async {
        let draft = pending ?? (UUID().uuidString.lowercased(), text, spoiler)
        pending = draft
        if await thread.reply(id: draft.0, text: draft.1, spoiler: draft.2) { pending = nil; text = ""; spoiler = false }
    }
}
private struct CommunityReportForm: View {
    let thread: CommunityThread; let comment: String?; let author: String; let completed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ReportReason.spam
    @State private var block = false
    var body: some View {
        NavigationStack {
            Form {
                Picker(L10n.text("Motivo"), selection: $reason) { ForEach(ReportReason.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                Toggle(L10n.text("Bloquear também este usuário"), isOn: $block)
                if let error = thread.error { AuthErrorBanner(message: error) }
                Button(L10n.text("ENVIAR DENÚNCIA")) { Task { if await thread.report(comment: comment, author: author, reason: reason, block: block) { completed() } } }.disabled(thread.busy)
            }.navigationTitle(L10n.text("DENUNCIAR"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("FECHAR")) { dismiss() }.disabled(thread.busy) } }
        }.interactiveDismissDisabled(thread.busy)
    }
}
