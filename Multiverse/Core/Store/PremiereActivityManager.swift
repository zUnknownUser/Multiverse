import ActivityKit
import Foundation

/// Inicia/atualiza/encerra a Live Activity de estreia, a partir do app (ver Interações 5f,
/// "Estreia ao vivo" — essa tela ainda vai ser construída; este manager já fica pronto).
@MainActor
enum PremiereActivityManager {
    static func start(itemTitle: String, question: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = PremiereActivityAttributes(itemTitle: itemTitle)
        let state = PremiereActivityAttributes.ContentState(
            question: question,
            optionALabel: "Obra-prima", optionAPercent: 0,
            optionBLabel: "Bom, mas…", optionBPercent: 0,
            optionCLabel: "Retcon criminoso", optionCPercent: 0,
            votingCountLabel: "0 votando", chosenIndex: nil
        )
        do {
            _ = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
        } catch {
            // Live Activities exigem `NSSupportsLiveActivities` no Info.plist e um device/
            // simulator real — sem isso, `Activity.request` lança e a gente só ignora aqui.
        }
    }

    static func update(_ state: PremiereActivityAttributes.ContentState) async {
        for activity in Activity<PremiereActivityAttributes>.activities {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    static func endAll() async {
        for activity in Activity<PremiereActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .default)
        }
    }
}
