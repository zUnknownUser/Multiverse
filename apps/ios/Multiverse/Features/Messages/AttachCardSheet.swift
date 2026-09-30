import SwiftUI

/// Sheet compacta pra anexar uma carta de obra direto na conversa, a partir do "+" do composer.
struct AttachCardSheet: View {
    let userID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Item] {
        guard !query.isEmpty else { return Array(store.items.prefix(30)) }
        return store.items.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { item in
                    let uni = store.universe(of: item)
                    Button {
                        store.sendCard(to: [userID], itemID: item.id, text: "")
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            PosterView(item: item, universe: uni, width: 40, height: 60, titleSize: 8, shadow: 0)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                                Text(uni.name.uppercased()).font(MVFont.black(9)).foregroundStyle(MV.C.muted)
                            }
                        }
                    }
                    .listRowBackground(MV.C.paper)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(MV.C.paper)
            .searchable(text: $query, prompt: L10n.text("Buscar obra…"))
            .navigationTitle(L10n.text("Mandar carta"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Cancelar")) { dismiss() }
                }
            }
        }
    }
}
