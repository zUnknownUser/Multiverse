import WidgetKit
import SwiftUI

/// Pequeno: "% do universo" — recurso 2a.
struct UniversePercentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UniversePercentWidget", provider: SnapshotProvider()) { entry in
            UniversePercentWidgetView(entry: entry)
                .containerBackground(MV.C.wow, for: .widget)
        }
        .configurationDisplayName("% do universo")
        .description("Quanto do cânone do seu universo principal você já viu.")
        .supportedFamilies([.systemSmall])
    }
}

private struct UniversePercentWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 6) {
            Text((snapshot?.universeName ?? "AZEROTH").uppercased())
                .font(MVFont.black(12)).foregroundStyle(MV.C.ink)
            Spacer(minLength: 0)
            Text("\(snapshot?.universePercent ?? 0)%")
                .font(MVFont.black(34)).foregroundStyle(MV.C.ink)
            ComicProgress(value: Double(snapshot?.universePercent ?? 0) / 100, fill: MV.C.ink, height: 8)
            if let delta = snapshot?.universePercentDelta, delta != 0 {
                Text("+\(delta)% este mês").font(MVFont.bold(10)).foregroundStyle(MV.C.ink)
            }
        }
        .padding(4)
    }
}
