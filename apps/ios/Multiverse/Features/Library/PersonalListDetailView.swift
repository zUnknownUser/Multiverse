import SwiftUI

struct PersonalListDetailView: View {
    let listID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var adding = false
    @State private var deleting = false
    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 18) {
                if let library = store.library {
                    LibraryStatusNotice(library: library)
                    if let list = library.lists.first(where: { $0.id == listID }) {
                        Text(L10n.text("LISTA PRIVADA")).kicker()
                        Text(list.title).font(MVFont.display(28, width: 118))
                        if !list.description.isEmpty { Text(list.description).font(MVFont.body(14)) }
                        HStack {
                            Button(L10n.text("ADICIONAR OBRAS")) { adding = true }
                            Spacer()
                            Menu {
                                Button(L10n.text("EDITAR LISTA")) { editing = true }
                                Button(L10n.text("EXCLUIR LISTA"), role: .destructive) { deleting = true }
                            } label: { Image(systemName: "ellipsis.circle").font(.title2) }.accessibilityLabel(L10n.text("Mais opções"))
                        }.disabled(!library.canMutate)
                        if list.itemIDs.isEmpty { LibraryEmptyState(message: L10n.text("Esta lista ainda não tem obras.")) }
                        ForEach(list.itemIDs, id: \.self) { id in
                            LibraryItemRow(itemID: id) { Task { await library.change("remove_item", listID: listID, itemID: id) } }.disabled(!library.canMutate)
                        }
                    } else if library.snapshot != nil && !library.busy { Text(L10n.text("Esta lista não está mais disponível.")) }
                }
            }.foregroundStyle(MV.C.ink).padding(MV.pad)
        }.task { await store.library?.refresh() }.refreshable { await store.library?.refresh() }
        .sheet(isPresented: $editing) { if let library = store.library, let list = library.lists.first(where: { $0.id == listID }) { PersonalListEditor(library: library, list: list) } }
        .sheet(isPresented: $adding) { LibraryItemPicker(listID: listID) }
        .confirmationDialog(L10n.text("Excluir esta lista? As obras e seu diário serão mantidos."), isPresented: $deleting, titleVisibility: .visible) {
            Button(L10n.text("EXCLUIR LISTA"), role: .destructive) { Task { if await store.library?.change("delete_list", listID: listID) == true { dismiss() } } }
        }
    }
}
private struct LibraryItemPicker: View {
    let listID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List {
                if let library = store.library {
                    LibraryStatusNotice(library: library)
                    if let list = library.lists.first(where: { $0.id == listID }) {
                        let results = store.items.filter { search.isEmpty || $0.title.localizedStandardContains(search) }
                        if results.isEmpty { Text(L10n.text("Nenhuma obra encontrada.")) }
                        ForEach(results) { item in
                            let included = list.itemIDs.contains(item.id)
                            Button {
                                Task { await library.change(included ? "remove_item" : "add_item", listID: listID, itemID: item.id) }
                            } label: {
                                HStack { Text(item.title).foregroundStyle(MV.C.ink); Spacer(); Image(systemName: included ? "checkmark.circle.fill" : "plus.circle") }
                            }.disabled(!library.canMutate)
                        }
                    } else { Text(L10n.text("Esta lista não está mais disponível.")) }
                }
            }.searchable(text: $search, prompt: L10n.text("Buscar obras"))
            .navigationTitle(L10n.text("ADICIONAR OBRAS"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("CONCLUÍDO")) { dismiss() } } }
        }
    }
}
struct AddItemToListSheet: View {
    let itemID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    var body: some View {
        NavigationStack {
            List {
                if let library = store.library {
                    LibraryStatusNotice(library: library)
                    Button(L10n.text("CRIAR LISTA")) { creating = true }.disabled(!library.canMutate)
                    if library.lists.isEmpty { Text(L10n.text("Crie sua primeira lista para organizar as obras.")) }
                    ForEach(library.lists) { list in
                        let included = list.itemIDs.contains(itemID)
                        Button { Task { await library.change(included ? "remove_item" : "add_item", listID: list.id, itemID: itemID) } } label: {
                            HStack { Text(list.title).foregroundStyle(MV.C.ink); Spacer(); Image(systemName: included ? "checkmark.circle.fill" : "plus.circle") }
                        }.disabled(!library.canMutate)
                    }
                }
            }.navigationTitle(L10n.text("ADICIONAR A LISTAS"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("CONCLUÍDO")) { dismiss() } } }
        }.task { await store.library?.refresh() }
        .sheet(isPresented: $creating) { if let library = store.library { PersonalListEditor(library: library) } }
    }
}
