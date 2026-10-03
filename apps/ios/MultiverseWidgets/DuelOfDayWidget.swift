import WidgetKit
import SwiftUI

/// Médio: "Duelo do dia" — recurso 2a.
struct DuelOfDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DuelOfDayWidget", provider: SnapshotProvider()) { entry in
            DuelOfDayWidgetView(entry: entry)
                .containerBackground(MV.C.ink, for: .widget)
        }
        .configurationDisplayName(L10n.text("Duelo do dia"))
        .description(L10n.text("A votação em aberto no seu círculo."))
        .supportedFamilies([.systemMedium])
    }
}

private struct DuelOfDayWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("DUELO DO DIA")).font(MVFont.black(11)).foregroundStyle(MV.C.paper)
                Spacer()
                Text(snapshot?.duelVotesLabel ?? "").font(MVFont.bold(10)).foregroundStyle(MV.C.accent)
            }
            Text(snapshot?.duelQuestion ?? "").font(MVFont.black(14)).foregroundStyle(MV.C.paper).lineLimit(2)
            HStack(spacing: 8) {
                sidePlate(title: snapshot?.duelSideATitle ?? "", color: MV.C.accent)
                Text("VS").font(MVFont.black(11)).foregroundStyle(MV.C.paper)
                sidePlate(title: snapshot?.duelSideBTitle ?? "", color: MV.C.marvel)
            }
        }
        .padding(4)
    }

    private func sidePlate(title: String, color: Color) -> some View {
        Text(title.uppercased())
            .font(MVFont.black(11))
            .foregroundStyle(color == MV.C.accent ? MV.C.ink : MV.C.paper)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .frame(height: 52)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: MV.R.sm))
    }
}
