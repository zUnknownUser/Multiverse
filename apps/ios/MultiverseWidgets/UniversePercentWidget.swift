import WidgetKit
import SwiftUI

/// Pequeno: "% do universo" — recurso 2a.
struct UniversePercentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UniversePercentWidget", provider: SnapshotProvider()) { entry in
            UniversePercentWidgetView(entry: entry)
                .containerBackground(MV.C.accent, for: .widget)
        }
        .configurationDisplayName(L10n.text("% do universo"))
        .description(L10n.text("Quanto do cânone do seu universo principal você já viu."))
        .supportedFamilies([.systemSmall])
    }
}

private struct UniversePercentWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 6) {
            Text((snapshot?.universeName ?? "MARVEL").uppercased())
                .font(MVFont.black(12)).foregroundStyle(MV.C.ink)
            Spacer(minLength: 0)
            Text("\(snapshot?.universePercent ?? 0)%")
                .font(MVFont.black(34)).foregroundStyle(MV.C.ink)
            ComicProgress(value: Double(snapshot?.universePercent ?? 0) / 100, fill: MV.C.ink, height: 8)
            if let delta = snapshot?.universePercentDelta, delta != 0 {
                Text(L10n.format("+%1$@%% este mês", String(describing: delta))).font(MVFont.bold(10)).foregroundStyle(MV.C.ink)
            }
        }
        .padding(4)
    }
}
