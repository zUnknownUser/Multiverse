import Foundation

/// Implementação em memória de `MultiverseRepository`, carregada a partir de
/// `Resources/sample-data.json`. É a única classe que conhece o JSON — `AppStore` e as
/// Views só falam com o protocolo `MultiverseRepository`.
actor MockRepository: MultiverseRepository {
    private let catalog: Catalog

    private var reviews: [Review]
    private var diary: [DiaryEntry]
    private var follows: Set<String>
    private var itemToggles = ItemToggles()
    private var reviewToggles = ReviewToggles()
    private var reactions: [String: ReactionType] = [:]
    private var conversations: [Conversation]
    private var messages: [Message]
    private var roomMessages: [RoomMessage]
    private var roomProgress: [String: Int] = [:]
    private var pollVotes = PollVotes()
    private var orderState = OrderState()
    private var likedLists: Set<String> = []

    private let recursos: RecursosData
    private var shieldState: ShieldState
    private var clubState: ClubState
    private var clubMessages: [ClubMessage]
    private var theoryLoreState: TheoryLoreState
    private var predictionState: PredictionState
    private var correctionSuggestions: [CorrectionSuggestion]

    /// Simula latência de rede pra que estados de loading façam sentido; ajuste/zere se quiser.
    private let simulatedLatency: Duration = .milliseconds(220)

    init(sample: SampleData = .load(), startFollowing: Bool, session: AuthSession? = nil) {
        let signedInUser = session.map {
            User(id: $0.userID, name: $0.displayName ?? L10n.text("Lorista"), handle: $0.handle,
                 avatarColor: $0.avatarColor ?? "#F4A814", bio: $0.bio ?? "", followers: 0, badgeUniverse: "")
        }
        catalog = Catalog(
            universes: sample.universes, items: sample.items, users: sample.users + (signedInUser.map { [$0] } ?? []),
            badgeNames: sample.badgeNames, connections: sample.connections, timelines: sample.timelines,
            readingOrders: sample.readingOrders, lists: sample.lists, genericReviewTexts: sample.genericReviewTexts,
            canonStatus: sample.canonStatus, canonStatusColors: sample.canonStatusColors, duels: sample.duels, me: session.map { Me(id: $0.userID, following: [], followers: 0) } ?? sample.me
        )
        follows = startFollowing ? ["nina", "caio", "leo", "bia", "rafa", "tati"] : []

        var initial = sample.reviews.map { review -> Review in
            var r = review
            r.comments = r.comments.map { c in var c2 = c; c2.when = c2.when ?? "1h"; return c2 }
            return r
        }
        initial.append(contentsOf: MockRepository.generatedReviews(items: sample.items, genericTexts: sample.genericReviewTexts))
        reviews = initial

        diary = MockRepository.initialDiary()

        recursos = .load()
        shieldState = ShieldState(points: ["dc": 4, "marvel": 3], advanceAutomatically: true)
        clubState = ClubState(
            memberUnits: ["c-crises|nina": 12, "c-crises|duda": 11, "c-crises|gui": 7, "c-crises|bia": 2],
            heartedMessages: [], powedMessages: []
        )
        clubMessages = recursos.clubMessages
        theoryLoreState = TheoryLoreState(points: 40, accuracyPercent: 66)
        predictionState = PredictionState(points: 1240, answers: ["pq1": .choice(1)])
        correctionSuggestions = recursos.correctionSuggestions
        conversations = recursos.conversations
        messages = recursos.messages
        roomMessages = recursos.roomMessages
        roomProgress = ["d-crise": 1]
        if session != nil {
            // Real identities must not inherit the demo account's personal activity.
            follows = []
            diary = []
            itemToggles = ItemToggles(seenOverrides: [:], wanted: [], liked: [])
            orderState = OrderState(upvoted: [], following: [])
            shieldState = ShieldState()
            clubState = ClubState()
            theoryLoreState = TheoryLoreState(points: 0, accuracyPercent: 0)
            predictionState = PredictionState()
            conversations = []
            messages = []
            roomProgress = [:]
        }
    }

    private func delay() async {
        try? await Task.sleep(for: simulatedLatency)
    }


    // MARK: - Catálogo

    func loadCatalog() async throws -> Catalog {
        await delay()
        return catalog
    }

    // MARK: - Feed / reviews / comentários

    func fetchReviews() async throws -> [Review] {
        await delay()
        return reviews
    }

    func publishReview(_ review: Review) async throws {
        reviews.insert(review, at: 0)
    }

    func fetchReviewToggles() async throws -> ReviewToggles {
        await delay()
        return reviewToggles
    }

    func setReviewLiked(reviewID: String, liked: Bool) async throws {
        if liked { reviewToggles.liked.insert(reviewID) } else { reviewToggles.liked.remove(reviewID) }
    }

    func postComment(reviewID: String, comment: Comment) async throws {
        guard let idx = reviews.firstIndex(where: { $0.id == reviewID }) else { return }
        reviews[idx].comments.append(comment)
    }

    func setCommentLiked(reviewID: String, commentIndex: Int, liked: Bool) async throws {
        let key = "\(reviewID):\(commentIndex)"
        if liked { reviewToggles.likedComments.insert(key) } else { reviewToggles.likedComments.remove(key) }
    }

    func setSpoilerRevealed(reviewID: String) async throws {
        reviewToggles.revealedSpoilers.insert(reviewID)
    }

    func fetchReactions() async throws -> [String: ReactionType] {
        await delay()
        return reactions
    }

    func setReaction(reviewID: String, type: ReactionType?) async throws {
        reactions[reviewID] = type
    }

    // MARK: - Itens

    func fetchItemToggles() async throws -> ItemToggles {
        await delay()
        return itemToggles
    }

    func setItemSeen(itemID: String, seen: Bool) async throws {
        itemToggles.seenOverrides[itemID] = seen
    }

    func setItemWanted(itemID: String, wanted: Bool) async throws {
        if wanted { itemToggles.wanted.insert(itemID) } else { itemToggles.wanted.remove(itemID) }
    }

    func setItemLiked(itemID: String, liked: Bool) async throws {
        if liked { itemToggles.liked.insert(itemID) } else { itemToggles.liked.remove(itemID) }
    }

    // MARK: - Votos

    func fetchPollVotes() async throws -> PollVotes {
        await delay()
        return pollVotes
    }

    func submitPollVote(topic: PollTopic, optionIndex: Int) async throws {
        switch topic {
        case .weekly:
            guard pollVotes.weekly == nil else { return }
            pollVotes.weekly = optionIndex
        case .essential(let id):
            guard pollVotes.essential[id] == nil else { return }
            pollVotes.essential[id] = optionIndex
        case .canon(let id):
            guard pollVotes.canon[id] == nil else { return }
            pollVotes.canon[id] = optionIndex
        case .duel(let i):
            guard pollVotes.duel[i] == nil else { return }
            pollVotes.duel[i] = optionIndex
        case .theory(let id):
            guard pollVotes.theory[id] == nil else { return }
            pollVotes.theory[id] = optionIndex
        }
    }

    // MARK: - Follows

    func fetchFollows() async throws -> Set<String> {
        await delay()
        return follows
    }

    func setFollowing(userID: String, following: Bool) async throws {
        if following { follows.insert(userID) } else { follows.remove(userID) }
    }

    // MARK: - Diário

    func fetchDiary() async throws -> [DiaryEntry] {
        await delay()
        return diary
    }

    func addDiaryEntry(_ entry: DiaryEntry) async throws {
        diary.insert(entry, at: 0)
    }

    // MARK: - Ordens

    func fetchOrderState() async throws -> OrderState {
        await delay()
        return orderState
    }

    func setOrderUpvoted(orderID: String, upvoted: Bool) async throws {
        if upvoted { orderState.upvoted.insert(orderID) } else { orderState.upvoted.remove(orderID) }
    }

    func setOrderFollowing(orderID: String, following: Bool) async throws {
        if following { orderState.following.insert(orderID) } else { orderState.following.remove(orderID) }
    }

    // MARK: - Listas

    func fetchLikedLists() async throws -> Set<String> {
        await delay()
        return likedLists
    }

    func setListLiked(listID: String, liked: Bool) async throws {
        if liked { likedLists.insert(listID) } else { likedLists.remove(listID) }
    }

    // MARK: - Escudo de spoiler

    func fetchShieldState() async throws -> ShieldState {
        await delay()
        return shieldState
    }

    func setShieldPoint(universeID: String, timelineIndex: Int) async throws {
        shieldState.points[universeID] = timelineIndex
    }

    func setShieldAdvanceAutomatically(_ enabled: Bool) async throws {
        shieldState.advanceAutomatically = enabled
    }

    // MARK: - Clubes de maratona

    func fetchClubs() async throws -> [Club] {
        await delay()
        return recursos.clubs
    }

    func fetchClubMessages(clubID: String) async throws -> [ClubMessage] {
        await delay()
        return clubMessages.filter { $0.clubID == clubID }
    }

    func postClubMessage(_ message: ClubMessage) async throws {
        clubMessages.append(message)
    }

    func fetchClubState() async throws -> ClubState {
        await delay()
        return clubState
    }

    func setClubUnitsCompleted(clubID: String, units: Int) async throws {
        clubState.memberUnits["\(clubID)|duda"] = units
    }

    func setClubMessageHearted(messageID: String, hearted: Bool) async throws {
        if hearted { clubState.heartedMessages.insert(messageID) } else { clubState.heartedMessages.remove(messageID) }
        guard let idx = clubMessages.firstIndex(where: { $0.id == messageID }) else { return }
        clubMessages[idx].hearts += hearted ? 1 : -1
    }

    func addClubMessagePow(messageID: String) async throws {
        guard !clubState.powedMessages.contains(messageID) else { return }
        clubState.powedMessages.insert(messageID)
        guard let idx = clubMessages.firstIndex(where: { $0.id == messageID }) else { return }
        clubMessages[idx].pows += 1
    }

    // MARK: - Teorias

    func fetchTheories() async throws -> [Theory] {
        await delay()
        return recursos.theories
    }

    func postTheory(_ theory: Theory) async throws {
        // Amostra em memória — persistir uma teoria nova exigiria `theories` ser `var`;
        // deixado de fora de propósito (ver README de limitações) pra não desviar do escopo mock.
    }

    func fetchTheoryLoreState() async throws -> TheoryLoreState {
        await delay()
        return theoryLoreState
    }

    // MARK: - Previsões

    func fetchPredictionEvents() async throws -> [PredictionEvent] {
        await delay()
        return recursos.predictionEvents
    }

    func fetchPredictionState() async throws -> PredictionState {
        await delay()
        return predictionState
    }

    func submitPredictionAnswer(questionID: String, answer: PredictionAnswer) async throws {
        predictionState.answers[questionID] = answer
    }

    // MARK: - Denúncia

    func submitReport(_ report: ReportSubmission) async throws {
        await delay()
        // Mock: nada pra persistir além do toast que a View já mostra.
    }

    // MARK: - Sugerir correção

    func fetchCorrectionSuggestions(itemID: String) async throws -> [CorrectionSuggestion] {
        await delay()
        return correctionSuggestions.filter { $0.itemID == itemID }
    }

    func submitCorrection(_ suggestion: CorrectionSuggestion) async throws {
        correctionSuggestions.append(suggestion)
    }

    // MARK: - Onde assistir

    func fetchWatchAvailability(itemID: String) async throws -> WatchAvailability? {
        await delay()
        return recursos.watchAvailability.first { $0.itemID == itemID }
    }

    // MARK: - Mensagens e cartas

    func fetchConversations() async throws -> [Conversation] {
        await delay()
        return conversations
    }

    func fetchMessages(conversationID: String) async throws -> [Message] {
        await delay()
        return messages.filter { $0.conversationID == conversationID }
    }

    func sendMessage(_ message: Message) async throws {
        messages.append(message)
        if let idx = conversations.firstIndex(where: { $0.userID == message.conversationID }) {
            conversations[idx].lastPreview = message.text ?? L10n.text("mandou uma carta")
            conversations[idx].lastWhen = L10n.text("agora")
        }
    }

    func respondToDuelChallenge(messageID: String, choice: Int) async throws {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[idx].duelChallenge?.responderChoice = choice
    }

    func markConversationRead(_ conversationID: String) async throws {
        guard let idx = conversations.firstIndex(where: { $0.userID == conversationID }) else { return }
        conversations[idx].unreadCount = 0
    }

    // MARK: - Salas por obra

    func fetchRooms() async throws -> [Room] {
        await delay()
        return recursos.rooms
    }

    func fetchRoomMessages(itemID: String) async throws -> [RoomMessage] {
        await delay()
        return roomMessages.filter { $0.itemID == itemID }
    }

    func postRoomMessage(_ message: RoomMessage) async throws {
        roomMessages.append(message)
    }

    func fetchRoomProgress() async throws -> [String: Int] {
        await delay()
        return roomProgress
    }

    func setRoomProgress(itemID: String, segmentIndex: Int) async throws {
        roomProgress[itemID] = segmentIndex
    }

    // MARK: - Estreia ao vivo

    func fetchLiveEvent() async throws -> LiveEvent? {
        await delay()
        return recursos.liveEvent
    }

    // MARK: - Geração determinística (idêntica ao protótipo HTML)

    private static func generatedReviews(items: [Item], genericTexts: [String]) -> [Review] {
        let pool = StaticContent.suggestionUserIDs
        var out: [Review] = []
        for (i, item) in items.enumerated() {
            for j in 0...1 {
                let sd = Logic.seed(item.id + String(j))
                let offset = (Double(Int(sd % 3)) - 1) * 0.5
                let raw = ((item.avg + offset) * 2).rounded() / 2
                let rating = max(1, min(5, raw))
                let text = genericTexts[Int(sd) % genericTexts.count]
                let likes = 20 + Int(sd % 400)
                let when = L10n.format("%1$@ dias", String(describing: 2 + Int(sd % 20)))
                var comments: [Comment] = []
                if sd % 2 == 1 {
                    let commenter = pool[(i + j + 1) % pool.count]
                    comments = [Comment(user: commenter, text: L10n.text("Concordo demais."), likes: Int(sd % 9), when: L10n.text("4 dias"))]
                }
                let author = pool[(i + j) % pool.count]
                out.append(Review(id: "g-\(item.id)-\(j)", user: author, item: item.id, rating: rating, text: text, spoiler: false, likes: likes, when: when, comments: comments))
            }
        }
        return out
    }

    private static func initialDiary() -> [DiaryEntry] {
        let calendar = Calendar(identifier: .gregorian)
        return [
            ("m-secret", 27, 9, 4.5, true, false),
            ("m-civil", 24, 9, 5, false, true),
            ("d-crise", 19, 9, 4, false, false),
            ("m-loki", 12, 9, 3.5, false, false),
            ("m-ultimato", 3, 9, 5, true, false),
            ("d-watchmen", 28, 8, 5, true, false),
            ("m-civil", 20, 8, 3, false, false),
            ("e-superman", 14, 8, 3.5, false, false),
            ("d-flash", 9, 8, 4, false, false),
        ].compactMap { itemID, day, month, rating, liked, rewatch in
            guard let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)) else { return nil }
            return DiaryEntry(itemId: itemID, loggedAt: date, rating: rating, liked: liked, rewatch: rewatch)
        }
    }
}
