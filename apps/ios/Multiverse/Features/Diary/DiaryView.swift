import SwiftUI

struct DiaryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var groupedByMonth: [DiaryMonth] { DiaryTimeline.months(store.diary) }

    private var yearRange: String {
        let dates = store.diary.map(\.loggedAt)
        let first = L10n.date(dates.min() ?? .now, template: "yyyy")
        let last = L10n.date(dates.max() ?? .now, template: "yyyy")
        return first == last ? first : "\(first)–\(last)"
    }

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 22) {
                ActivityRefreshNotice()
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("DIÁRIO")).font(MVFont.display(30, width: 122)).foregroundStyle(MV.C.ink)
                    Text(store.diary.isEmpty ? L10n.text("Nenhum registro ainda") : L10n.format("diary.recordCount", store.diary.count) + " · " + yearRange)
                        .font(MVFont.body(13, weight: 600)).foregroundStyle(MV.C.muted)
                }

                if store.diary.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Seu diário começa com o primeiro registro."))
                            .font(MVFont.body(14)).foregroundStyle(MV.C.muted)
                        PrimaryAuthButton(title: L10n.text("FAZER PRIMEIRO REGISTRO")) { store.openLogBlank() }
                    }
                }

                ForEach(groupedByMonth) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(L10n.date(group.start, template: Calendar.current.isDate(group.start, equalTo: .now, toGranularity: .year) ? "LLLL" : "LLLL yyyy").uppercased())
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
        .refreshable { await store.refreshActivity() }
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
                    Text("\(Calendar.current.component(.day, from: entry.loggedAt))").font(MVFont.black(24)).foregroundStyle(MV.C.ink).frame(width: 34, alignment: .leading)
                    PosterView(item: item, universe: uni, width: 34, height: 51, titleSize: 7, showLabel: false)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                        Text("\(L10n.text(item.type)) · \(uni.name)").font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
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
