import Foundation

/// Conteúdo estático do protótipo que não está no sample-data.json
/// (notificações, ranking, listas curadas). Ver `<script>` do HTML de referência.
enum StaticContent {

    struct NotificationItem: Identifiable {
        let id = UUID()
        let userID: String
        let text: String
        let itemID: String?
        let quote: String?
        let when: String
        let reviewID: String?
        let isNewFollower: Bool
    }

    static let notifications: [NotificationItem] = [
        .init(userID: "nina", text: "curtiu sua review de", itemID: "w-wotlk", quote: nil, when: "12 min", reviewID: "r9", isNewFollower: false),
        .init(userID: "caio", text: "respondeu sua review de", itemID: "d-crise", quote: "“Pré-Crise é superior e eu morro nessa colina.”", when: "1h", reviewID: "r10", isNewFollower: false),
        .init(userID: "gui", text: "começou a seguir você", itemID: nil, quote: nil, when: "3h", reviewID: nil, isNewFollower: true),
        .init(userID: "leo", text: "votou na sua ordem de leitura", itemID: nil, quote: nil, when: "5h", reviewID: nil, isNewFollower: false),
        .init(userID: "bia", text: "e mais 18 curtiram sua review de", itemID: "w-wotlk", quote: nil, when: "ontem", reviewID: "r9", isNewFollower: false),
        .init(userID: "mari", text: "começou a seguir você", itemID: nil, quote: nil, when: "2 dias", reviewID: nil, isNewFollower: true),
        .init(userID: "tati", text: "mencionou você em", itemID: "d-tdk", quote: "“@duda.lore precisa ver isso logo”", when: "3 dias", reviewID: "r6", isNewFollower: false),
    ]

    struct LeaderboardEntry: Identifiable {
        var id: String { userID }
        let userID: String
        let reviews: Int
        let likes: Int
    }

    static let leaderboard: [LeaderboardEntry] = [
        .init(userID: "gui", reviews: 48, likes: 9120),
        .init(userID: "leo", reviews: 36, likes: 6400),
        .init(userID: "mari", reviews: 29, likes: 4880),
        .init(userID: "joao", reviews: 22, likes: 3100),
    ]

    /// "Em alta no seu círculo" (Home)
    static let trendingItemIDs = ["w-wotlk", "m-aranha", "c-sylvanas", "d-tdk", "e-cataclismo", "d-watchmen"]

    /// Pool usado tanto pra reviews geradas quanto pras sugestões de seguir
    static let suggestionUserIDs = ["gui", "mari", "joao", "lu"]

    /// Grade curada do sheet de registro ("O que você viu, leu ou jogou?")
    static let logQuickPickIDs = ["w-cata", "m-aranha", "d-tdk", "w-arthas", "c-sylvanas", "e-estalo", "d-reino", "m-fenix", "d-injustice"]

    /// Favoritos fixos do perfil do usuário logado
    static let myFavoriteItemIDs = ["w-wc3", "d-watchmen", "m-fenix", "c-arthas"]

    static let comingSoonUniverses = ["Star Wars", "League of Legends", "Tolkien"]

    static let compatAgreeWorks = ["Watchmen", "Warcraft III", "Aranhaverso", "Reino do Amanhã"]
    static let compatAgreePeople = ["Thanos", "Arthas", "O Cavaleiro das Trevas"]
    static let compatDisagreeWorks = ["Cataclysm", "Sylvanas", "Guerra Civil", "Injustice"]

    static let wrappedArchetypeTitle = "O ARQUIVISTA"
    static let wrappedArchetypeNote = "Você revisita obras antigas e segue a cronologia à risca. 82% dos seus registros foram na ordem canônica."

    /// Base de votos do Debate da semana (Home) — fixo, independente de seed
    static let weeklyDebateOptions = ["Melhor momento da lore", "Pior retcon de todos", "Os dois ao mesmo tempo"]
    static let weeklyDebateBase = [1830, 1290, 1692]
    static let weeklyDebateComments = "612 comentários"

    /// Reputação em teorias dos autores de exemplo no feed de Teorias.
    static let theoryAccuracy: [String: Int] = ["joao": 71, "bia": 58, "caio": 49]

    /// Liga dos amigos em Previsões — "Você" entra dinamicamente via `AppStore.predictionPoints`.
    static let predictionLeague: [(userID: String, points: Int)] = [
        ("nina", 2310), ("caio", 980),
    ]
}
