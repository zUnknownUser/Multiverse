import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var filter: SearchFilter = .all

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 16) {
                Text("BUSCA").font(MVFont.display(28, width: 122)).foregroundStyle(MV.C.ink)

                searchField

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(SearchFilter.allCases, id: \.self) { f in
                            PillButton(title: f.rawValue, active: filter == f, size: 13) { filter = f }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                let (rows, total) = store.searchResults(query: query, filter: filter)
                Text(query.isEmpty ? "Mais registrados esta semana" : "\(total) resultados")
                    .kicker(11).foregroundStyle(MV.C.muted)

                if rows.isEmpty {
                    Text("Nada nesse canto do multiverso.")
                        .font(MVFont.body(14)).foregroundStyle(MV.C.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    VStack(spacing: 10) {
                        ForEach(rows) { row in
                            SearchResultRowView(row: row)
                        }
                    }
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Text("⌕").font(.system(size: 18, weight: .bold)).foregroundStyle(MV.C.muted)
            TextField("Obra, personagem, evento, pessoa…", text: $query)
                .font(MVFont.body(14, weight: 600))
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(MV.C.card)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .background(RoundedRectangle(cornerRadius: MV.R.xl).fill(MV.C.ink).offset(x: MV.Shadow.m, y: MV.Shadow.m))
    }
}

private struct SearchResultRowView: View {
    let row: SearchResultRow
    @Environment(AppStore.self) private var store

    var body: some View {
        Button {
            store.push(row.route)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    row.posterBG
                    if !row.initials.isEmpty {
                        Text(row.initials).font(MVFont.black(14)).foregroundStyle(row.posterFG)
                    }
                }
                .frame(width: 44, height: row.isCircular ? 44 : 64)
                .clipShape(row.isCircular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: MV.R.sm)))
                .overlay(
                    (row.isCircular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: MV.R.sm)))
                        .strokeBorder(MV.C.ink, lineWidth: MV.stroke)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title).font(MVFont.bold(14)).foregroundStyle(MV.C.ink).lineLimit(1)
                    Text(row.meta).font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted).lineLimit(1)
                }
                Spacer()
                Text(row.typeLabel.uppercased())
                    .font(MVFont.black(9)).tracking(0.3)
                    .foregroundStyle(row.pillFG)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(row.pillBG))
                    .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: 1.5))
            }
        }
        .buttonStyle(.plain)
    }
}
