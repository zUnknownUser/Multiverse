import Foundation
import Observation

enum CommunityError: LocalizedError {
    case unavailable, conflict, stale, invalidImage, closed, membership, clubUnavailable, ownerLeave, roomProgress, capacity, scheduleDate, mentionLimit, invalidDuel
    var errorDescription: String? {
        switch self {
        case .roomProgress: L10n.text("Este trecho contém spoilers. Atualize seu progresso para participar.")
        case .capacity: L10n.text("O limite deste recurso foi atingido. Tente novamente mais tarde ou remova conteúdo antigo.")
        case .scheduleDate: L10n.text("Já existe uma etapa nesta data. Escolha outra data.")
        case .mentionLimit: L10n.text("Você pode mencionar até 10 pessoas por mensagem.")
        case .invalidDuel: L10n.text("Use duas opções diferentes e uma data de encerramento nos próximos 30 dias.")
        case .stale: L10n.text("Esta publicação mudou em outro dispositivo. Feche e abra novamente para editar a versão atual.")
        case .invalidImage: L10n.text("Não foi possível enviar esta imagem. Escolha uma foto JPEG, PNG ou WebP de até 2 MB.")
        case .closed: L10n.text("A votação foi encerrada. Atualize para ver o resultado.")
        case .membership: L10n.text("Entre no clube para participar da conversa.")
        case .clubUnavailable: L10n.text("Este clube não está mais disponível para você.")
        case .ownerLeave: L10n.text("Você é o organizador. Para encerrar o clube, use Excluir clube.")
        case .unavailable: L10n.text("Esta publicação não está mais disponível para você.")
        case .conflict: L10n.text("Este envio já foi usado. Confira a comunidade antes de publicar novamente.")
        }
    }
}
@MainActor @Observable final class CommunityTimeline {
    private(set) var posts: [CommunityPost] = []
    private(set) var users: [String: User] = [:]
    private(set) var cursor: String?
    private(set) var busy = false
    private(set) var error: String?
    private var currentFilter: CommunityFilter?
    private var generation = 0
    func load(api: any CommunityAPI, universe: String?, item: String?, more: Bool = false) async {
        await load(api: api, filter: .init(universe: universe, item: item), more: more)
    }
    func load(api: any CommunityAPI, filter: CommunityFilter, more: Bool = false) async {
        if currentFilter != filter { generation += 1; currentFilter = filter; posts = []; users = [:]; cursor = nil; busy = false }
        let requestGeneration = generation
        guard !busy, !more || cursor != nil else { return }; busy = true; error = nil
        defer { if requestGeneration == generation { busy = false } }
        do {
            let after = more ? cursor : nil
            let page = try await api.fetchPosts(filter: filter, after: after)
            guard requestGeneration == generation else { return }
            try Task.checkCancellation(); try page.validate()
            guard page.nextCursor == nil || page.nextCursor != after,
                  page.posts.allSatisfy({ (filter.universe == nil || $0.universeID == filter.universe) && (filter.item == nil || $0.itemID == filter.item) && (filter.kind == nil || $0.kind == filter.kind) && (filter.club == nil || $0.clubID == filter.club) && (filter.schedule == nil || $0.scheduleID == filter.schedule) && (filter.segment == nil || $0.segment == filter.segment) }) else { throw SocialError.invalid }
            let previous = more ? posts : []
            posts = previous + page.posts.filter { post in !previous.contains(where: { $0.id == post.id }) }
            for user in page.users { users[user.id] = user }; cursor = page.nextCursor
        } catch is CancellationError { }
        catch { if requestGeneration == generation { self.error = error.localizedDescription } }
    }
}
@MainActor @Observable final class CommunityThread {
    private(set) var post: CommunityPost?
    private(set) var comments: [RemoteComment] = []
    private(set) var users: [String: User] = [:]
    private(set) var interactions: [String: InteractionSummary] = [:]
    private(set) var canComment = false
    private(set) var cursor: String?
    private(set) var busy = false
    private(set) var error: String?
    let api: any CommunityAPI; let id: String
    init(api: any CommunityAPI, id: String) { self.api = api; self.id = id }
    func load(more: Bool = false) async {
        guard !busy, !more || cursor != nil else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            if !more {
                let page = try await api.fetchPost(id); try page.validate()
                guard page.posts.count == 1, page.posts[0].id == id else { throw SocialError.invalid }
                post = page.posts[0]; interactions[id] = post?.interaction
                for user in page.users { users[user.id] = user }
            }
            let after = more ? cursor : nil
            let page = try await api.fetchPostComments(id, after: after)
            try Task.checkCancellation(); try page.validate(review: id)
            guard page.nextCursor == nil || page.nextCursor != after else { throw SocialError.invalid }
            let previous = more ? comments : []
            comments = previous + page.comments.filter { comment in !previous.contains(where: { $0.id == comment.id }) }
            for user in page.users { users[user.id] = user }
            for comment in page.comments { interactions[comment.id] = comment.interaction }
            canComment = page.canComment; cursor = page.nextCursor
        } catch is CancellationError { }
        catch {
            self.error = error.localizedDescription
            if error is CommunityError { post = nil; comments = []; canComment = false }
        }
    }
    func reply(id commentID: String, text: String, spoiler: Bool, parent: String? = nil) async -> Bool {
        guard !busy, canComment else { return false }; busy = true; error = nil
        do {
            let receipt = try await api.postReply(post: id, id: commentID, text: text, spoiler: spoiler, parent: parent)
            guard receipt.saved, receipt.reviewID == id, receipt.commentID == commentID else { throw SocialError.invalid }
            busy = false; await load(); return true
        } catch { self.error = error.localizedDescription; busy = false; return false }
    }
    func vote(_ choice: Int) async {
        guard !busy else { return }; busy = true; error = nil
        do {
            let receipt = try await api.votePost(id, choice: choice)
            guard receipt.saved, receipt.id == id else { throw SocialError.invalid }
            busy = false; await load()
        } catch { self.error = error.localizedDescription; busy = false }
    }
    func resolve(status: String, note: String) async -> Bool {
        guard !busy, let post else { return false }; busy = true; error = nil
        do {
            let receipt = try await api.resolveTheory(id, status: status, note: note, version: post.version ?? 1)
            guard receipt.saved, receipt.id == id else { throw SocialError.invalid }
            busy = false; await load(); return true
        } catch { self.error = error.localizedDescription; busy = false; return false }
    }
    func react(comment: String?, reaction: String?, liked: Bool) async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            let summary = try await api.reactToPost(id, comment: comment, reaction: reaction, liked: liked)
            try summary.validate(target: comment ?? id)
            guard summary.myReaction == reaction, summary.liked == liked else { throw SocialError.invalid }
            interactions[summary.id] = summary
        } catch { self.error = error.localizedDescription }
    }
    func report(comment: String?, author: String, reason: ReportReason, block: Bool) async -> Bool {
        guard !busy else { return false }; busy = true; error = nil
        do {
            if let comment {
                let r = try await api.reportPostComment(id, comment: comment, reason: reason.apiValue, alsoBlock: block)
                guard r.reported, r.reviewID == id, r.commentID == comment, r.blockedUserID == (block ? author : nil) else { throw SocialError.invalid }
            } else {
                let r = try await api.reportPost(id, reason: reason.apiValue, alsoBlock: block)
                guard r.reported, r.reviewID == id, r.blockedUserID == (block ? author : nil) else { throw SocialError.invalid }
            }
            comments = []; post = nil; canComment = false
            busy = false
            if comment != nil && !block { await load() }
            return true
        } catch { self.error = error.localizedDescription; busy = false; return false }
    }
    func delete() async -> Bool {
        guard !busy else { return false }; busy = true; error = nil
        defer { busy = false }
        do {
            let receipt = try await api.deletePost(id)
            guard receipt.deleted, receipt.id == id else { throw SocialError.invalid }
            post = nil; comments = []; return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
