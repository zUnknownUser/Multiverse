import SwiftUI

struct LibraryEmptyState: View {
    let message: String
    var body: some View {
        Text(message)
            .font(MVFont.body(14, weight: 500))
            .foregroundStyle(MV.C.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .comicCard(shadow: MV.Shadow.s)
    }
}

struct LibraryStatusNotice: View {
    let library: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if library.busy { ProgressView() }
            if let error = library.error { AuthErrorBanner(message: error) }
            if library.pending != nil {
                Text(L10n.text("Alteração pendente de confirmação. Tente novamente para concluir sem duplicar."))
                    .font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                Button(L10n.text("TENTAR DE NOVO")) { Task { await library.retry() } }.disabled(library.busy)
            } else if library.error != nil {
                Button(L10n.text("ATUALIZAR BIBLIOTECA")) { Task { await library.refresh() } }.disabled(library.busy)
            }
        }
    }
}
struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var selection = 0
    @State private var creating = false
    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("BIBLIOTECA")).font(MVFont.display(28, width: 118))
                Text(L10n.text("Seus desejos, favoritos e listas. Só você pode ver."))
                    .font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.muted)
                Picker(L10n.text("Biblioteca"), selection: $selection) {
                    Text(L10n.text("Quero consumir")).tag(0)
                    Text(L10n.text("Favoritos")).tag(1)
                    Text(L10n.text("Listas")).tag(2)
                }.pickerStyle(.segmented)
                if let library = store.library {
                    LibraryStatusNotice(library: library)
                    if library.snapshot != nil {
                        if selection == 2 {
                            Button(L10n.text("CRIAR LISTA")) { creating = true }.buttonStyle(.borderedProminent).disabled(!library.canMutate)
                            if library.lists.isEmpty { LibraryEmptyState(message: L10n.text("Crie sua primeira lista para organizar as obras.")) }
                            ForEach(library.lists) { list in PersonalListRow(list: list) }
                        } else {
                            let ids = selection == 0 ? library.wantedIDs : library.favoriteIDs
                            if ids.isEmpty { LibraryEmptyState(message: L10n.text("Nada salvo aqui ainda. Explore uma obra para começar.")) }
                            ForEach(ids, id: \.self) { id in
                                LibraryItemRow(itemID: id) {
                                    Task { await library.change(selection == 0 ? "wanted" : "favorite", itemID: id, enabled: false) }
                                }.disabled(!library.canMutate)
                            }
                        }
                    }
                }
            }.foregroundStyle(MV.C.ink).padding(MV.pad)
        }.task { await store.library?.refresh() }.refreshable { await store.library?.refresh() }
        .sheet(isPresented: $creating) { if let library = store.library { PersonalListEditor(library: library) } }
    }
}
struct PersonalListRow: View {
    let list: PersonalList
    @Environment(AppStore.self) private var store
    var body: some View {
        Button { store.push(.list(list.id)) } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle").font(.title2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(list.title).font(MVFont.bold(15))
                    Text(L10n.format("%1$@ obras · lista privada", String(list.itemIDs.count))).font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                }
                Spacer(); Image(systemName: "chevron.right")
            }.foregroundStyle(MV.C.ink).padding(14).comicCard()
        }.buttonStyle(.plain)
    }
}
struct LibraryItemRow: View {
    let itemID: String
    let remove: () -> Void
    @Environment(AppStore.self) private var store
    var body: some View {
        HStack(spacing: 12) {
            if let item = store.item(itemID) {
                Button { store.push(.item(item.id)) } label: {
                    HStack(spacing: 12) {
                        PosterView(item: item, universe: store.universe(of: item), width: 42, height: 63, titleSize: 7)
                        Text(item.title).font(MVFont.bold(14)).multilineTextAlignment(.leading)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            } else {
                Text(L10n.text("Obra indisponível no catálogo")).font(MVFont.body(14)).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }
                .accessibilityLabel(L10n.text("Remover da seleção"))
        }.foregroundStyle(MV.C.ink).padding(12).comicCard()
    }
}
struct PersonalListEditor: View {
    let library: LibraryStore
    var list: PersonalList? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var id = UUID().uuidString.lowercased()
    @State private var title = ""
    @State private var description = ""
    @State private var attempted = false
    var body: some View {
        NavigationStack {
            Form {
                Text(L10n.text("Esta lista é privada. Só você pode acessar e editar."))
                TextField(L10n.text("Nome da lista"), text: $title).disabled(library.busy || library.pending != nil)
                TextField(L10n.text("Descrição (opcional)"), text: $description, axis: .vertical).lineLimit(3...6).disabled(library.busy || library.pending != nil)
                Text("\(title.unicodeScalars.count)/100 · \(description.unicodeScalars.count)/1000").font(.caption)
                if let error = library.error { AuthErrorBanner(message: error) }
                if library.pending != nil { Text(L10n.text("Alteração pendente de confirmação. Tente novamente para concluir sem duplicar.")) }
                Button(library.pending == nil ? L10n.text("SALVAR LISTA") : L10n.text("TENTAR DE NOVO")) {
                    Task {
                        attempted = true
                        let saved = library.pending != nil ? await library.retry() : await library.change(list == nil ? "create_list" : "update_list", listID: list?.id ?? id, title: title, description: description)
                        if saved { dismiss() }
                    }
                }.disabled(library.busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.unicodeScalars.count > 100 || description.unicodeScalars.count > 1000)
            }.navigationTitle(list == nil ? L10n.text("CRIAR LISTA") : L10n.text("EDITAR LISTA"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("FECHAR")) { dismiss() }.disabled(library.busy) } }
        }.onAppear { if !attempted { title = list?.title ?? ""; description = list?.description ?? "" } }
        .interactiveDismissDisabled(library.busy || library.pending != nil)
    }
}
