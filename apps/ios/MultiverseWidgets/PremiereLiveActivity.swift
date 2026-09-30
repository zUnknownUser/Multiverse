import ActivityKit
import WidgetKit
import SwiftUI

/// Live Activity de "Estreia ao vivo" — recurso 2b. Tela de bloqueio em modo Noir com
/// enquete relâmpago; Dynamic Island compacta mostra só o logo M + %.
struct PremiereLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PremiereActivityAttributes.self) { context in
            lockScreenView(attributes: context.attributes, state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    logoBadge
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(L10n.text("● AO VIVO")).font(MVFont.bold(11)).foregroundStyle(MV.C.marvel)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    optionsList(state: context.state)
                }
            } compactLeading: {
                logoBadge
            } compactTrailing: {
                Text("\(context.state.optionAPercent)%").font(MVFont.bold(13)).foregroundStyle(MV.C.wow)
            } minimal: {
                logoBadge
            }
        }
    }

    private var logoBadge: some View {
        Text("M")
            .font(MVFont.black(13))
            .foregroundStyle(MV.C.paper)
            .frame(width: 24, height: 24)
            .background(MV.C.marvel)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func lockScreenView(attributes: PremiereActivityAttributes, state: PremiereActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                logoBadge
                Text(L10n.text("● AO VIVO"))
                    .font(MVFont.bold(11))
                    .foregroundStyle(MV.C.paper)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(MV.C.marvel)
                    .clipShape(Capsule())
                Spacer()
                Text(state.votingCountLabel).font(MVFont.bold(11)).foregroundStyle(MV.C.wow)
            }
            Text(L10n.format("ESTREIA · %1$@", String(describing: state.question)).uppercased())
                .font(MVFont.black(15)).foregroundStyle(MV.C.paper).lineLimit(2)
            optionsList(state: state)
        }
        .padding(16)
        .activityBackgroundTint(MV.C.ink)
        .activitySystemActionForegroundColor(MV.C.paper)
    }

    private func optionsList(state: PremiereActivityAttributes.ContentState) -> some View {
        VStack(spacing: 6) {
            optionRow(state.optionALabel, state.optionAPercent, chosen: state.chosenIndex == 0)
            optionRow(state.optionBLabel, state.optionBPercent, chosen: state.chosenIndex == 1)
            optionRow(state.optionCLabel, state.optionCPercent, chosen: state.chosenIndex == 2)
        }
    }

    private func optionRow(_ label: String, _ percent: Int, chosen: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                MV.C.ink.opacity(0.4)
                Rectangle().fill(chosen ? MV.C.wow : MV.C.ink.opacity(0.15))
                    .frame(width: geo.size.width * Double(percent) / 100)
                HStack {
                    Text((chosen ? "✓ " : "") + label).font(MVFont.bold(12)).foregroundStyle(MV.C.paper)
                    Spacer()
                    Text("\(percent)%").font(MVFont.bold(12)).foregroundStyle(MV.C.paper)
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
