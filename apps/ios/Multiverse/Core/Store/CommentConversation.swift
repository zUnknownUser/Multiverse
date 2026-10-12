import Foundation
import Observation

struct CommentContextPage: Codable, Sendable {
    let reviewID: String
    let targetID: String
    let comments: [RemoteComment]
    let users: [User]
    let canComment: Bool
    let truncated: Bool

    func validate(post: String, target: String) throws {
        try CommentsPage(reviewID: reviewID, canComment: canComment, comments: comments, users: users, nextCursor: nil).validate(review: post)
        guard targetID == target, comments.last?.id == target,
              !truncated || comments.first?.parentID != nil else { throw SocialError.invalid }
        for (index, comment) in comments.enumerated() {
            guard comment.parentID == nil || (UUID(uuidString: comment.parentID!) != nil && comment.isReply == true),
                  index == 0 || comment.parentID == comments[index - 1].id else { throw SocialError.invalid }
        }
        guard !comments.contains(where: { $0.id == comments.first?.parentID }) else { throw SocialError.invalid }
    }
}

/// Loaded replies keep chronological order. Walking child edges once also handles
/// replies arriving on a later page without reordering unrelated conversations.
struct CommentConversation {
    let byID: [String: RemoteComment]
    let visible: [RemoteComment]

    init(comments: [RemoteComment], collapsed: Set<String>) {
        var index: [String: RemoteComment] = [:]
        var children: [String: [String]] = [:]
        for comment in comments {
            index[comment.id] = comment
            if let parent = comment.parentID { children[parent, default: []].append(comment.id) }
        }
        var hidden: Set<String> = []
        var pending = collapsed.filter { index[$0] != nil }.flatMap { children[$0] ?? [] }
        while let id = pending.popLast() {
            guard hidden.insert(id).inserted else { continue }
            pending.append(contentsOf: children[id] ?? [])
        }
        byID = index
        visible = comments.filter { !hidden.contains($0.id) }
    }

    func ancestors(of id: String) -> Set<String> {
        var result: Set<String> = []
        var current: String? = id
        while let id = current, result.insert(id).inserted { current = byID[id]?.parentID }
        return result
    }
}

/// Context is isolated from the paginated discussion so opening a reply never
/// replaces the reader's pages, scroll position, or collapsed branches.
@MainActor @Observable final class CommentContext {
    private(set) var comments: [RemoteComment] = []
    private(set) var users: [String: User] = [:]
    private(set) var busy = false
    private(set) var error: String?
    private(set) var earlierID: String?
    let api: any CommunityAPI
    let postID: String
    let targetID: String

    init(api: any CommunityAPI, post: String, target: String) {
        self.api = api; postID = post; targetID = target
    }

    func load(earlier: Bool = false) async {
        guard !busy, !earlier || earlierID != nil else { return }
        let requested = earlier ? earlierID! : targetID
        busy = true; error = nil
        defer { busy = false }
        do {
            let page = try await api.fetchCommentContext(post: postID, comment: requested)
            try Task.checkCancellation()
            try page.validate(post: postID, target: requested)
            let known = Set(comments.map(\.id))
            if earlier {
                guard comments.first?.parentID == requested,
                      page.comments.allSatisfy({ !known.contains($0.id) }),
                      page.comments.first?.parentID.map({ !known.contains($0) }) ?? true else { throw SocialError.invalid }
            }
            comments = page.comments + (earlier ? comments : [])
            if !earlier { users = [:] }
            for user in page.users { users[user.id] = user }
            earlierID = page.truncated ? page.comments.first?.parentID : nil
        } catch is CancellationError { }
        catch {
            self.error = error.localizedDescription
            if error is CommunityError || (error as? SocialError) == .commentUnavailable {
                comments = []; users = [:]; earlierID = nil
            }
        }
    }
}
