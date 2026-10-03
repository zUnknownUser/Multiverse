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
        .init(userID: "nina", text: L10n.text("curtiu sua review de"), itemID: "d-crise", quote: nil, when: "12 min", reviewID: "r10", isNewFollower: false),
        .init(userID: "caio", text: L10n.text("respondeu sua review de"), itemID: "d-crise", quote: L10n.text("“Pré-Crise é superior e eu morro nessa colina.”"), when: "1h", reviewID: "r10", isNewFollower: false),
        .init(userID: "gui", text: L10n.text("começou a seguir você"), itemID: nil, quote: nil, when: "3h", reviewID: nil, isNewFollower: true),
        .init(userID: "leo", text: L10n.text("votou na sua ordem de leitura"), itemID: nil, quote: nil, when: "5h", reviewID: nil, isNewFollower: false),
        .init(userID: "bia", text: L10n.text("e mais 18 curtiram sua review de"), itemID: "d-crise", quote: nil, when: L10n.text("ontem"), reviewID: "r10", isNewFollower: false),
        .init(userID: "mari", text: L10n.text("começou a seguir você"), itemID: nil, quote: nil, when: L10n.text("2 dias"), reviewID: nil, isNewFollower: true),
        .init(userID: "tati", text: L10n.text("mencionou você em"), itemID: "d-tdk", quote: L10n.text("“@duda.lore precisa ver isso logo”"), when: L10n.text("3 dias"), reviewID: "r6", isNewFollower: false),
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
    static let trendingItemIDs = ["m-civil", "m-aranha", "c-loki", "d-tdk", "e-superman", "d-watchmen"]

    /// Pool usado tanto pra reviews geradas quanto pras sugestões de seguir
    static let suggestionUserIDs = ["gui", "mari", "joao", "lu"]

    /// Grade curada do sheet de registro ("O que você viu, leu ou jogou?")
    static let logQuickPickIDs = ["d-flash", "m-aranha", "d-tdk", "m-secret", "c-loki", "e-estalo", "d-reino", "m-fenix", "d-injustice"]

    /// Favoritos fixos do perfil do usuário logado
    static let myFavoriteItemIDs = ["m-ultimato", "d-watchmen", "m-fenix", "c-wanda"]

    static let comingSoonUniverses: [String] = []

    static let compatAgreeWorks = ["Watchmen", "Loki", L10n.text("Aranhaverso"), L10n.text("Reino do Amanhã")]
    static let compatAgreePeople = ["Thanos", "Wanda", L10n.text("O Cavaleiro das Trevas")]
    static let compatDisagreeWorks = ["Flashpoint", "Loki", L10n.text("Guerra Civil"), "Injustice"]

    static let wrappedArchetypeTitle = L10n.text("O ARQUIVISTA")
    static let wrappedArchetypeNote = L10n.text("Você revisita obras antigas e segue a cronologia à risca. 82% dos seus registros foram na ordem canônica.")

    /// Base de votos do Debate da semana (Home) — fixo, independente de seed
    static let weeklyDebateOptions = [L10n.text("Melhor momento da lore"), L10n.text("Pior retcon de todos"), L10n.text("Os dois ao mesmo tempo")]
    static let weeklyDebateBase = [1830, 1290, 1692]
    static let weeklyDebateComments = L10n.text("612 comentários")

    /// Reputação em teorias dos autores de exemplo no feed de Teorias.
    static let theoryAccuracy: [String: Int] = ["joao": 71, "bia": 58, "caio": 49]

    /// Liga dos amigos em Previsões — "Você" entra dinamicamente via `AppStore.predictionPoints`.
    static let predictionLeague: [(userID: String, points: Int)] = [
        ("nina", 2310), ("caio", 980),
    ]
}
