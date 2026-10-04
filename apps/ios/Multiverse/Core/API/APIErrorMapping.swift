import Foundation

/// Endpoint-domain errors stay outside token refresh, retries and HTTP decoding.
protocol APIErrorMapping: Sendable {
    func responseError(code: String?, status: Int, path: String) -> any Error
    func networkError(_ error: any Error, path: String) -> any Error
}

struct MultiverseAPIErrorMapper: APIErrorMapping {
    func networkError(_ error: any Error, path: String) -> any Error {
        if (error as? URLError)?.code == .timedOut, path.hasPrefix("me/diary/") { return ActivityError.timedOut }
        return AuthError.networkUnavailable
    }
    func responseError(code: String?, status: Int, path: String) -> any Error {
        switch code {
        case "ORDER_UNAVAILABLE": return ReadingOrdersError.unavailable
        case "ORDER_STALE": return ReadingOrdersError.stale
        case "ORDER_CONFLICT": return ReadingOrdersError.conflict
        case "ORDER_LIMIT": return ReadingOrdersError.limit
        case "INVALID_ORDER_REQUEST": return ReadingOrdersError.invalid
        case "MESSAGE_UNAVAILABLE": return DirectMessageError.unavailable
        case "MESSAGE_REQUEST_PENDING": return DirectMessageError.pending
        case "MESSAGE_CONFLICT": return DirectMessageError.conflict
        case "MESSAGE_LIMIT": return DirectMessageError.limit
        case "INVALID_MESSAGE": return SocialError.invalid
        case "VOICE_UNAVAILABLE": return VoiceError.unavailable
        case "VOICE_FULL": return VoiceError.full
        case "VOICE_BLOCKED": return VoiceError.blocked
        case "VOICE_SESSION_ENDED": return VoiceError.ended
        case "VOICE_SESSION_CONFLICT": return VoiceError.conflict

        case "LIBRARY_STALE": return LibraryError.stale
        case "LIST_UNAVAILABLE": return LibraryError.unavailable
        case "LIBRARY_MUTATION_CONFLICT", "LIBRARY_LIST_CONFLICT": return LibraryError.conflict
        case "LIBRARY_LISTS_LIMIT": return LibraryError.listLimit
        case "LIST_ITEMS_LIMIT": return LibraryError.itemLimit
        case "LIBRARY_ITEMS_LIMIT": return LibraryError.savedLimit
        case "INVALID_LIBRARY_REQUEST": return SocialError.invalid

        case "COMMENTS_RESTRICTED": return SocialError.commentsRestricted
        case "COMMENT_UNAVAILABLE": return SocialError.commentUnavailable
        case "COMMENT_LIMIT": return SocialError.commentLimit
        case "COMMENT_CONFLICT": return SocialError.commentConflict
        case "REACTION_LIMIT": return SocialError.reactionLimit
        case "POST_STALE": return CommunityError.stale
        case "INVALID_IMAGE": return CommunityError.invalidImage
        case "ROOM_PROGRESS_REQUIRED": return CommunityError.roomProgress
        case "CLUB_FULL", "CLUB_LIMIT", "SCHEDULE_LIMIT", "IMAGE_LIMIT": return CommunityError.capacity
        case "SCHEDULE_DATE_USED": return CommunityError.scheduleDate
        case "MENTION_LIMIT": return CommunityError.mentionLimit
        case "INVALID_DUEL": return CommunityError.invalidDuel
        case "VOTE_CLOSED": return CommunityError.closed
        case "CLUB_MEMBERSHIP_REQUIRED": return CommunityError.membership
        case "CLUB_UNAVAILABLE": return CommunityError.clubUnavailable
        case "CLUB_OWNER_CANNOT_LEAVE": return CommunityError.ownerLeave
        case "POST_UNAVAILABLE": return CommunityError.unavailable
        case "POST_CONFLICT": return CommunityError.conflict
        case "INVALID_POST_CATALOG": return CatalogError.changed
        case "REVIEW_UNAVAILABLE": return SocialError.unavailable
        case "INVALID_SOCIAL_REQUEST", "INVALID_REPORT", "INVALID_BLOCK", "INVALID_FEED_CURSOR": return SocialError.invalid
        case "REPORT_LIMIT": return SocialError.reportLimit
        case "PUBLICATION_LIMIT": return SocialError.publicationLimit
        case "PERSON_UNAVAILABLE": return PeopleError.unavailable
        case "INVALID_PEOPLE_QUERY": return PeopleError.invalidSearch
        case "INVALID_FOLLOW", "CANNOT_FOLLOW_SELF", "INVALID_PERSON": return PeopleError.followFailed
        case "ONBOARDING_REQUIRED": return PeopleError.onboardingRequired
        case "USERNAME_TAKEN": return AuthError.usernameTaken
        case "CATALOG_CHANGED": return CatalogError.changed
        case "INVALID_LOG": return ActivityError.invalidLog
        case "INVALID_LOG_DATE": return ActivityError.invalidDate
        case "ITEM_UNAVAILABLE": return ActivityError.itemUnavailable
        case "EMAIL_NOT_VERIFIED": return AuthError.emailNotVerified
        case "RECENT_LOGIN_REQUIRED": return AuthError.recentLoginRequired
        case "STALE_ONBOARDING", "ONBOARDING_COMPLETED": return AuthError.onboardingConflict
        case "FOLLOWS_REQUIRED", "INVALID_FOLLOWS": return AuthError.suggestionsChanged
        case "DELETION_PENDING", "ACCOUNT_DELETING": return AuthError.deletionPending
        default:
            if status == 401 { return AuthError.sessionExpired }
            if status == 429 { return AuthError.tooManyRequests }
            if path.hasPrefix("me/diary/") {
                if status == 413 { return ActivityError.tooLong }
                if status == 400 { return ActivityError.invalidLog }
            }
            if status == 400 { return AuthError.invalidProfile }
            return AuthError.apiUnavailable
        }
    }
}
