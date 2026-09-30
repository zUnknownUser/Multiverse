import SwiftUI

struct ListDetailView: View {
    let listID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            if let list = store.lists.first(where: { $0.id == listID }) {
                let liked = store.isListLiked(list.id)
                VStack(alignment: .leading, spacing: 16) {
                    Text("LISTA DE @\(store.user(store.meID)?.handle.dropFirst() ?? "")").kicker(11).foregroundStyle(MV.C.muted)
                    Text(list.title).font(MVFont.display(28, width: 118)).foregroundStyle(MV.C.ink)
                    Text(list.desc).font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)

                    HStack(spacing: 10) {
                        Text("♥ \(Logic.fmt(store.listLikeCount(list)))")
                            .font(MVFont.bold(12))
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .foregroundStyle(liked ? MV.C.card : MV.C.ink)
                            .background(liked ? MV.C.marvel : MV.C.card)
                            .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                            .clipShape(Capsule())
                            .burstOnTap("POW!", color: MV.C.marvel, when: !liked) {
                                store.toggleListLiked(list.id)
                            }
                        Text("\(list.comments) comentários").font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.muted)
                    }

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(list.items.enumerated()), id: \.offset) { index, itemID in
                            if let item = store.item(itemID) {
                                ListPosterCell(item: item, position: index + 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, MV.pad)
                .padding(.bottom, 24)
            }
        }
    }
}

private struct ListPosterCell: View {
    let item: Item
    let position: Int
    @Environment(AppStore.self) private var store

    var body: some View {
        Button { store.push(.item(item.id)) } label: {
            ZStack(alignment: .topLeading) {
                PosterView(item: item, universe: store.universe(of: item), width: 108, height: 162, titleSize: 11)
                Text("\(position)")
                    .font(MVFont.black(12))
                    .foregroundStyle(MV.C.paper)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(MV.C.ink))
                    .overlay(Circle().strokeBorder(MV.C.paper, lineWidth: 1.5))
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
    }
}
