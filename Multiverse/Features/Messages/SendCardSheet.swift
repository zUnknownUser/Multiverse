import SwiftUI

/// "Mandar carta" — recurso 5d. Aberta a partir de qualquer card compartilhável
/// (obra, review, duelo, teoria, lista, ordem) ou do "+" da conversa.
struct SendCardSheet: View {
    var itemID: String? = nil
    var preselectedUserIDs: [String] = []
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var selected: Set<String> = []

    private var friends: [User] {
        store.users.filter { store.follows.contains($0.id) }
    }

    private var item: Item? { itemID.flatMap { store.item($0) } }
    private var isSpoilerItem: Bool { item.map { store.isAheadOfShield($0) } ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let item {
                        cardPreview(item: item)
                    }

                    TextField("Escreva uma mensagem (opcional)…", text: $text, axis: .vertical)
                        .font(MVFont.body(14, weight: 500))
                        .padding(12)
                        .background(MV.C.card)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))

                    if isSpoilerItem {
                        HStack(alignment: .top, spacing: 8) {
                            Text("◆").foregroundStyle(MV.C.dc)
                            Text("Quem estiver atrás na timeline vai ver essa carta escondida pelo Escudo de Spoiler, até decidir revelar.")
                                .font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.ink)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .comicCard(bg: MV.C.dc.opacity(0.2), radius: MV.R.md, shadow: 0, dashed: true)
                    }

                    friendPicker
                }
                .padding(MV.pad)
            }
            .background(MV.C.paper)
            .navigationTitle("Mandar carta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { sendBar }
            .onAppear { selected = Set(preselectedUserIDs) }
        }
    }

    private func cardPreview(item: Item) -> some View {
        let uni = store.universe(of: item)
        return HStack(spacing: 12) {
            PosterView(item: item, universe: uni, width: 64, height: 96, titleSize: 11, shadow: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(MVFont.bold(15)).foregroundStyle(MV.C.ink)
                Text(uni.name.uppercased()).font(MVFont.black(10)).foregroundStyle(MV.C.muted)
                Text(String(format: "%.1f ★", item.avg)).font(MVFont.black(13)).foregroundStyle(MV.C.ink)
            }
            Spacer()
        }
        .padding(14)
        .background(uni.color.opacity(0.3))
        .overlay(RoundedRectangle(cornerRadius: MV.R.lg).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.lg))
        .rotationEffect(.degrees(-2))
        .padding(.vertical, 6)
    }

    private var friendPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRA QUEM?").kicker(11).foregroundStyle(MV.C.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 14) {
                ForEach(friends) { friend in
                    let isSelected = selected.contains(friend.id)
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottomTrailing) {
                            AvatarView(user: friend, size: 54)
                                .opacity(isSelected ? 1 : 0.55)
                            if isSelected {
                                Text("✓")
                                    .font(MVFont.black(11))
                                    .foregroundStyle(MV.C.paper)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(MV.C.ink))
                            }
                        }
                        Text(friend.name.components(separatedBy: " ").first ?? friend.name)
                            .font(MVFont.body(10, weight: 600)).foregroundStyle(MV.C.ink).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelected { selected.remove(friend.id) } else { selected.insert(friend.id) }
                    }
                }
            }
        }
    }

    private var sendBar: some View {
        Text(selected.isEmpty ? "ENVIAR" : "ENVIAR PRA \(selected.count)")
            .font(MVFont.bold(14))
            .frame(maxWidth: .infinity).frame(height: 50)
            .foregroundStyle(MV.C.paper)
            .background(selected.isEmpty ? MV.C.muted : MV.C.ink)
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
            .contentShape(Rectangle())
            .padding(MV.pad)
            .background(MV.C.paper)
            .overlay(alignment: .top) { Rectangle().fill(MV.C.ink).frame(height: MV.stroke) }
            .onTapGesture {
                guard !selected.isEmpty else { return }
                if let itemID {
                    store.sendCard(to: Array(selected), itemID: itemID, text: text)
                }
                dismiss()
            }
    }
}
