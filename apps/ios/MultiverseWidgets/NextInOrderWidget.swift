import WidgetKit
import SwiftUI

/// Pequeno: "Próximo na ordem" — recurso 2a.
struct NextInOrderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextInOrderWidget", provider: SnapshotProvider()) { entry in
            NextInOrderWidgetView(entry: entry)
                .containerBackground(MV.C.card, for: .widget)
        }
        .configurationDisplayName("Próximo na ordem")
        .description("O próximo item da ordem de leitura que você segue.")
        .supportedFamilies([.systemSmall])
    }
}

private struct NextInOrderWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 6) {
            Text("PRÓXIMO NA ORDEM").font(MVFont.black(10)).foregroundStyle(MV.C.muted)
            Text((snapshot?.nextOrderItemTitle ?? "—").uppercased())
                .font(MVFont.black(15))
                .foregroundStyle(MV.C.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            HStack {
                Text("\(snapshot?.nextOrderDone ?? 0) de \(snapshot?.nextOrderTotal ?? 0)")
                    .font(MVFont.bold(11)).foregroundStyle(MV.C.muted)
                Spacer()
            }
            ComicProgress(value: (snapshot?.nextOrderTotal ?? 0) > 0 ? Double(snapshot!.nextOrderDone) / Double(snapshot!.nextOrderTotal) : 0, fill: MV.C.wow, height: 8)
        }
        .padding(4)
    }
}
