import ActivityKit

/// Live Activity de "Estreia ao vivo" (recursos 2b / 5f). Compilado nos dois targets — é o
/// contrato entre o app (que inicia/atualiza via `PremiereActivityManager`) e a extensão de
/// widgets (que desenha a tela de bloqueio e a Dynamic Island).
struct PremiereActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var question: String
        var optionALabel: String
        var optionAPercent: Int
        var optionBLabel: String
        var optionBPercent: Int
        var optionCLabel: String
        var optionCPercent: Int
        var votingCountLabel: String
        var chosenIndex: Int?
    }

    var itemTitle: String
}
