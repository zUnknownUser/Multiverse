import Foundation
import Observation

enum CommunityError: LocalizedError {
    case unavailable, conflict
    var errorDescription: String? {
        switch self {
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
    func load(api: any CommunityAPI, universe: String?, item: String?, more: Bool = false) async {
        guard !busy, !more || cursor != nil else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            let after = more ? cursor : nil
            let page = try await api.fetchPosts(universe: universe, item: item, after: after)
            try Task.checkCancellation(); try page.validate()
            guard page.nextCursor == nil || page.nextCursor != after,
                  page.posts.allSatisfy({ (universe == nil || $0.universeID == universe) && (item == nil || $0.itemID == item) }) else { throw SocialError.invalid }
            let previous = more ? posts : []
            posts = previous + page.posts.filter { post in !previous.contains(where: { $0.id == post.id }) }
            for user in page.users { users[user.id] = user }; cursor = page.nextCursor
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
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
    func reply(id commentID: String, text: String, spoiler: Bool) async -> Bool {
        guard !busy, canComment else { return false }; busy = true; error = nil
        do {
            let receipt = try await api.postReply(post: id, id: commentID, text: text, spoiler: spoiler)
            guard receipt.saved, receipt.reviewID == id, receipt.commentID == commentID else { throw SocialError.invalid }
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
