import SwiftUI

struct DiaryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var groupedByMonth: [(month: String, entries: [DiaryEntry])] {
        var order: [String] = []
        var groups: [String: [DiaryEntry]] = [:]
        for entry in store.diary {
            if groups[entry.month] == nil { order.append(entry.month) }
            groups[entry.month, default: []].append(entry)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DIÁRIO").font(MVFont.display(30, width: 122)).foregroundStyle(MV.C.ink)
                    Text("\(store.diary.count) registros em 2026 · visível pros seus seguidores")
                        .font(MVFont.body(13, weight: 600)).foregroundStyle(MV.C.muted)
                }

                ForEach(groupedByMonth, id: \.month) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(group.month.uppercased())
                                .font(MVFont.black(11)).tracking(0.4)
                                .foregroundStyle(MV.C.paper)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(MV.C.ink)
                            Rectangle().fill(MV.C.ink).frame(height: 2)
                        }
                        VStack(spacing: 12) {
                            ForEach(group.entries) { entry in
                                DiaryRow(entry: entry)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
    }
}

private struct DiaryRow: View {
    let entry: DiaryEntry
    @Environment(AppStore.self) private var store

    var body: some View {
        guard let item = store.item(entry.itemId) else { return AnyView(EmptyView()) }
        let uni = store.universe(of: item)

        return AnyView(
            Button { store.push(.item(item.id)) } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(entry.day)").font(MVFont.black(24)).foregroundStyle(MV.C.ink).frame(width: 34, alignment: .leading)
                    PosterView(item: item, universe: uni, width: 34, height: 51, titleSize: 7, showLabel: false)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                        Text("\(item.type) · \(uni.name)").font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                        StarsText(rating: entry.rating, color: uni.color, size: 13)
                    }
                    Spacer()
                    VStack(spacing: 4) {
                        if entry.liked { Text("♥").foregroundStyle(MV.C.marvel) }
                        if entry.rewatch { Text("↻").foregroundStyle(MV.C.ink) }
                    }
                    .font(.system(size: 14, weight: .bold))
                }
            }
            .buttonStyle(.plain)
        )
    }
}
