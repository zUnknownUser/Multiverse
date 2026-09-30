import SwiftUI

/// Lista compacta de amigos pra escolher quem desafiar/chamar — usada pelo card de Duelo da Home.
struct FriendPickerSheet: View {
    let title: String
    let onPick: (String) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.users.filter { store.follows.contains($0.id) }) { friend in
                    Button {
                        onPick(friend.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(user: friend, size: 40)
                            Text(friend.name).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                        }
                    }
                    .listRowBackground(MV.C.paper)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(MV.C.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
    }
}
