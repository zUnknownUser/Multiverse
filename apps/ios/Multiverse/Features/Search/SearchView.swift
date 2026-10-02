import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var filter: SearchFilter = .all
    @State private var visibleResults = 40
    @State private var waitingForSearch = false
    private var searchingPeople: Bool { store.usesRemotePeople && (filter == .people || (filter == .all && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("BUSCA")).font(MVFont.display(28, width: 122)).foregroundStyle(MV.C.ink)

                searchField

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(SearchFilter.allCases, id: \.self) { f in
                            PillButton(title: L10n.text(f.rawValue), active: filter == f, size: 13) { filter = f }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                if query.isEmpty && store.showsDemoFeatures {
                    Button { store.push(.exploreRooms) } label: {
                        HStack(spacing: 8) {
                            Text(L10n.text("● SALAS AO VIVO")).font(MVFont.bold(12)).foregroundStyle(MV.C.ink)
                            Spacer()
                            Text(L10n.text("EXPLORAR →")).font(MVFont.bold(11)).foregroundStyle(MV.C.muted)
                        }
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(MV.C.card)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    }
                    .buttonStyle(.plain)
                }

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (filter == .all || filter == .works) {
                    CatalogSeriesSection()
                }

                let (rows, total) = store.searchResults(query: query, filter: filter, limit: visibleResults)
                Text(searchingPeople ? L10n.text("RESULTADOS") : (query.isEmpty ? L10n.text(store.usesRemoteCatalog ? "Explore o catálogo" : "Mais registrados esta semana") : L10n.format("search.results", total)))
                    .kicker(11).foregroundStyle(MV.C.muted)

                if searchingPeople, let people = store.people {
                    if let error = people.searchError {
                        PeopleStatusNotice(message: error) { await people.search(more: !people.searchIDs.isEmpty && people.nextCursor != nil) }
                    }
                    if people.isSearching || waitingForSearch { ProgressView().frame(maxWidth: .infinity) }
                }
                if rows.isEmpty && !(searchingPeople && (waitingForSearch || store.people?.isSearching == true || store.people?.searchError != nil || store.people?.searchQuery != query.trimmingCharacters(in: .whitespacesAndNewlines))) {
                    Text(store.usesAccountAPI && !store.usesRemotePeople && filter == .people
                         ? L10n.text("A busca por loristas estará disponível em breve. Enquanto isso, explore as obras do catálogo.")
                         : searchingPeople && filter == .people
                         ? L10n.text("Nenhum lorista encontrado. Tente outro nome ou volte mais tarde.")
                         : query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? L10n.text("Ainda não há itens nesta categoria. Experimente outro filtro.")
                         : L10n.text("Nenhum resultado para esta busca. Tente outro nome ou filtro."))
                        .font(MVFont.body(14)).foregroundStyle(MV.C.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(rows) { row in
                            SearchResultRowView(row: row)
                                .onAppear {
                                    if row.id == rows.last?.id && rows.count < total {
                                        visibleResults = min(total, visibleResults + 40)
                                    }
                                }
                        }
                    }
                }
                if searchingPeople, let people = store.people, people.nextCursor != nil {
                    PrimaryAuthButton(title: L10n.text("VER MAIS")) {
                        Task {
                            await people.search(more: true)
                            visibleResults += 20
                        }
                    }
                    .disabled(people.isSearching)
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
            .onChange(of: query) { _, _ in visibleResults = 40 }
            .onChange(of: filter) { _, _ in visibleResults = 40 }
        }
        .task(id: filter.rawValue + "|" + query + "|" + String(store.people?.discoveryEpoch ?? 0)) {
            guard let people = store.people else { return }
            waitingForSearch = searchingPeople
            people.prepareSearch(query)
            guard searchingPeople else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            waitingForSearch = false
            await people.search()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Text("⌕").font(.system(size: 18, weight: .bold)).foregroundStyle(MV.C.muted)
            TextField(L10n.text("Obra, personagem, evento, pessoa…"), text: $query)
                .font(MVFont.body(14, weight: 600))
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(MV.C.card)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .background(RoundedRectangle(cornerRadius: MV.R.xl).fill(MV.C.shadow).offset(x: MV.Shadow.m, y: MV.Shadow.m))
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
                .overlay {
                    if row.isCircular {
                        Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke)
                    } else {
                        RoundedRectangle(cornerRadius: MV.R.sm)
                            .strokeBorder(MV.C.ink, lineWidth: MV.stroke)
                    }
                }

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
