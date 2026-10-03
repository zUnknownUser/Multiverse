import WidgetKit
import SwiftUI

/// Pequeno: "Próximo na ordem" — recurso 2a.
struct NextInOrderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextInOrderWidget", provider: SnapshotProvider()) { entry in
            NextInOrderWidgetView(entry: entry)
                .containerBackground(MV.C.card, for: .widget)
        }
        .configurationDisplayName(L10n.text("Próximo na ordem"))
        .description(L10n.text("O próximo item da ordem de leitura que você segue."))
        .supportedFamilies([.systemSmall])
    }
}

private struct NextInOrderWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("PRÓXIMO NA ORDEM")).font(MVFont.black(10)).foregroundStyle(MV.C.muted)
            Text((snapshot?.nextOrderItemTitle ?? "—").uppercased())
                .font(MVFont.black(15))
                .foregroundStyle(MV.C.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            HStack {
                Text(L10n.format("%1$@ de %2$@", String(describing: snapshot?.nextOrderDone ?? 0), String(describing: snapshot?.nextOrderTotal ?? 0)))
                    .font(MVFont.bold(11)).foregroundStyle(MV.C.muted)
                Spacer()
            }
            ComicProgress(value: (snapshot?.nextOrderTotal ?? 0) > 0 ? Double(snapshot!.nextOrderDone) / Double(snapshot!.nextOrderTotal) : 0, fill: MV.C.accent, height: 8)
        }
        .padding(4)
    }
}
