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
    @State private var pending: (id: String, text: String, spoiler: Bool, parent: String?)?
    @State private var replyTo: RemoteComment?
    @State private var mentioning = false
    @State private var editing = false
    @State private var resolving = false
    @State private var reportTarget: ReportTarget?
    @State private var deleting = false
    @FocusState private var replyFocused: Bool
    private struct ReportTarget: Identifiable { let id: String; let comment: String?; let author: String }
    var body: some View {
        ScrollViewReader { proxy in
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
                            MentionedText(text: post.text, mentions: post.mentions ?? []).font(MVFont.body(15, weight: 500))
                            ForEach(post.images ?? []) { image in CommunityImageView(post: post.id, image: image) }
                            if post.kind == "theory" || post.kind == "duel" { PostVotingView(post: post, thread: thread) }
                        }
                        if post.editedAt != nil { Text(L10n.text("Editado")).font(MVFont.body(11, weight: 500)).foregroundStyle(MV.C.muted) }
                        reactions(comment: nil)
                        if post.user == store.meID {
                            Button(L10n.text("EDITAR PUBLICAÇÃO")) { editing = true }.disabled(thread.busy)
                            if post.kind == "theory" { Button(L10n.text("ATUALIZAR CONCLUSÃO")) { resolving = true } }
                            Button(L10n.text("EXCLUIR PUBLICAÇÃO"), role: .destructive) { deleting = true }
                        } else {
                            Button(L10n.text("DENUNCIAR")) { reportTarget = .init(id: post.id, comment: nil, author: post.user) }
                        }
                    }.padding(14).comicCard()
                    Text(L10n.text("COMENTÁRIOS")).font(MVFont.section(18))
                    ForEach(thread.comments) { comment in
                        VStack(alignment: .leading, spacing: 10) {
                            author(comment.user)
                            if comment.isReply == true {
                                if let parent = thread.comments.first(where: { $0.id == comment.parentID }), let person = thread.users[parent.user] {
                                    Label(L10n.format("Em resposta a %1$@", person.handle), systemImage: "arrowshape.turn.up.left").font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                                } else { Text(L10n.text("Resposta a um comentário anterior.")).font(MVFont.body(11, weight: 500)).foregroundStyle(MV.C.muted) }
                            }
                            if comment.spoiler && !revealed.contains(comment.id) {
                                Button(L10n.text("REVELAR SPOILER")) { revealed.insert(comment.id) }
                            } else { MentionedText(text: comment.text, mentions: comment.mentions ?? []).font(MVFont.body(14, weight: 500)) }
                            reactions(comment: comment.id)
                            if thread.canComment { Button(L10n.text("RESPONDER")) { replyTo = comment }.disabled(thread.busy || pending != nil) }
                            if comment.user != store.meID {
                                Button(L10n.text("DENUNCIAR")) { reportTarget = .init(id: comment.id, comment: comment.id, author: comment.user) }.font(MVFont.body(11, weight: 700))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).comicCard().padding(.leading, comment.isReply == true ? 14 : 0)
                    }
                    if thread.cursor != nil { Button(L10n.text("CARREGAR MAIS")) { Task { await thread.load(more: true) } }.disabled(thread.busy) }
                    if thread.canComment {
                        VStack(alignment: .leading, spacing: 10) {
                            if let replyTo {
                                HStack {
                                    Text(L10n.format("Em resposta a %1$@", thread.users[replyTo.user]?.handle ?? "")).font(MVFont.bold(12))
                                    Spacer(); Button(L10n.text("CANCELAR")) { self.replyTo = nil }.disabled(thread.busy || pending != nil)
                                }
                            }
                            Button(L10n.text("MENCIONAR PESSOA")) { mentioning = true }.disabled(thread.busy || pending != nil)
                            TextField(L10n.text("Escreva um comentário"), text: $text, axis: .vertical).focused($replyFocused).lineLimit(3...8).disabled(thread.busy || pending != nil)
                            Toggle(L10n.text("Contém spoiler"), isOn: $spoiler).disabled(thread.busy || pending != nil)
                            if pending != nil { Text(L10n.text("Envio pendente. Tente novamente para confirmar sem duplicar sua publicação.")).font(.caption) }
                            Button(L10n.text("ENVIAR")) { Task { await reply() } }.disabled(thread.busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.unicodeScalars.count > 2000)
                        }.padding(14).comicCard().id("reply-composer")
                    } else { Text(L10n.text("O autor limitou quem pode comentar.")) }
                }
            }.foregroundStyle(MV.C.ink).padding(MV.pad)
        }.task { await thread.load() }.refreshable { await thread.load() }
        .confirmationDialog(L10n.text("Excluir esta publicação?"), isPresented: $deleting, titleVisibility: .visible) {
            Button(L10n.text("EXCLUIR PUBLICAÇÃO"), role: .destructive) { Task { if await thread.delete() { dismiss() } } }
        }
        .sheet(isPresented: $mentioning) { MentionPicker { user in text += (text.isEmpty || text.hasSuffix(" ") ? "" : " ") + user.handle + " " } }
        .sheet(isPresented: $editing, onDismiss: { Task { await thread.load() } }) {
            if let post = thread.post { PostComposer(universe: post.universeID, item: post.itemID, kind: post.kind ?? "discussion", club: post.clubID, schedule: post.scheduleID, editing: post) }
        }
        .sheet(isPresented: $resolving) { TheoryResolutionForm(thread: thread) }
        .sheet(item: $reportTarget) { target in
            CommunityReportForm(thread: thread, comment: target.comment, author: target.author) {
                reportTarget = nil
                store.social?.invalidateFeed()
                Task { await store.notifications?.refresh() }
                if target.comment == nil || thread.post == nil { dismiss() }
            }
        }
        .onChange(of: replyTo?.id) { _, newValue in
            if newValue != nil { withAnimation { proxy.scrollTo("reply-composer", anchor: .bottom) }; replyFocused = true }
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
        let draft = pending ?? (UUID().uuidString.lowercased(), text, spoiler, replyTo?.id)
        pending = draft
        if await thread.reply(id: draft.0, text: draft.1, spoiler: draft.2, parent: draft.3) { pending = nil; text = ""; spoiler = false; replyTo = nil }
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
private struct PostVotingView: View {
    let post: CommunityPost; let thread: CommunityThread
    private var closed: Bool { (post.closesAt.map { $0 <= .now } ?? false) || (post.resolution ?? "open") != "open" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if post.kind == "theory" {
                Text(L10n.text("Plausibilidade da teoria")).font(MVFont.bold(14))
                if (post.resolution ?? "open") != "open" {
                    Text(post.resolution == "confirmed" ? L10n.text("CONFIRMADA PELO AUTOR") : L10n.text("REFUTADA PELO AUTOR")).kicker()
                    if let note = post.resolutionNote { Text(note).font(MVFont.body(13, weight: 500)) }
                }
            }
            let options = post.kind == "theory" ? [L10n.text("Plausível"), L10n.text("Viajou")] : [post.optionA ?? "", post.optionB ?? ""]
            let counts = post.votes?.counts ?? [0, 0]
            ForEach(0..<2) { choice in
                Button { Task { await thread.vote(choice) } } label: {
                    HStack { Text(options[choice]); Spacer(); if post.votes?.mine == choice { Image(systemName: "checkmark.circle.fill") }; Text("\(counts.indices.contains(choice) ? counts[choice] : 0)") }
                        .font(MVFont.bold(14)).foregroundStyle(MV.C.ink).padding(12).comicCard(shadow: MV.Shadow.s)
                }.buttonStyle(.plain).disabled(thread.busy || closed)
            }
            if let closesAt = post.closesAt {
                HStack { Text(closed ? L10n.text("Votação encerrada") : L10n.text("Encerra em")); Text(closesAt, style: .date); Text(closesAt, style: .time) }.font(MVFont.body(11, weight: 500))
            }
        }
    }
}
private struct TheoryResolutionForm: View {
    let thread: CommunityThread
    @Environment(\.dismiss) private var dismiss
    @State private var status = "confirmed"
    @State private var note = ""
    var body: some View {
        NavigationStack {
            Form {
                Text(L10n.text("Explique sua conclusão e cite a obra ou fonte. A marcação ficará identificada como conclusão do autor."))
                Picker(L10n.text("Conclusão"), selection: $status) {
                    Text(L10n.text("Aberta")).tag("open")
                    Text(L10n.text("Confirmada")).tag("confirmed")
                    Text(L10n.text("Refutada")).tag("refuted")
                }
                TextField(L10n.text("Fonte e explicação"), text: $note, axis: .vertical).lineLimit(3...8)
                if let error = thread.error { AuthErrorBanner(message: error) }
                Button(L10n.text("SALVAR ALTERAÇÕES")) { Task { if await thread.resolve(status: status, note: note) { dismiss() } } }.disabled(thread.busy || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.unicodeScalars.count > 1000)
            }.navigationTitle(L10n.text("ATUALIZAR CONCLUSÃO"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("FECHAR")) { dismiss() }.disabled(thread.busy) } }
        }.interactiveDismissDisabled(thread.busy)
    }
}
