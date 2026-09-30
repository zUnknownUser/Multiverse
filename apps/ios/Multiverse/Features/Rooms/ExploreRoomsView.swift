import SwiftUI

private enum RoomFilter: String, CaseIterable { case todas = "Todas", aoVivo = "Ao vivo", proximas = "Próximas" }

/// "Explorar salas" — recurso 5i.
struct ExploreRoomsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var filter: RoomFilter = .todas
    @State private var notifyMe = false

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("SALAS")).font(MVFont.display(30, width: 122)).foregroundStyle(MV.C.ink)
                    .padding(.horizontal, MV.pad)

                if let event = store.liveEvent, let item = store.item(event.itemID) {
                    premierePromo(event: event, item: item).padding(.horizontal, MV.pad)
                }

                filterPills.padding(.horizontal, MV.pad)

                VStack(spacing: 10) {
                    ForEach(filteredRooms) { room in
                        RoomRow(room: room)
                    }
                }
                .padding(.horizontal, MV.pad)
            }
            .padding(.bottom, 24)
        }
    }

    private var filteredRooms: [Room] {
        switch filter {
        case .todas: return store.rooms
        case .aoVivo: return store.rooms.filter { $0.onlineCount > 0 }
        case .proximas: return store.rooms.filter { $0.onlineCount == 0 }
        }
    }

    private var filterPills: some View {
        HStack(spacing: 8) {
            ForEach(RoomFilter.allCases, id: \.self) { f in
                let selected = filter == f
                Text(L10n.text(f.rawValue).uppercased())
                    .font(MVFont.bold(11))
                    .padding(.horizontal, 12).frame(height: 34)
                    .foregroundStyle(selected ? MV.C.paper : MV.C.ink)
                    .background(selected ? MV.C.ink : MV.C.card)
                    .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(Capsule())
                    .contentShape(Rectangle())
                    .onTapGesture { filter = f }
            }
        }
    }

    private func premierePromo(event: LiveEvent, item: Item) -> some View {
        let uni = store.universe(of: item)
        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                uni.color
                Halftone(color: uni.inkColor.opacity(0.18))
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("HOJE 21H")).font(MVFont.black(11)).foregroundStyle(uni.color)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(uni.inkColor)
                        .clipShape(Capsule())
                    Text(L10n.text("ESTREIA AO VIVO")).kicker(10).foregroundStyle(uni.inkColor.opacity(0.75))
                    Text(item.title.uppercased()).font(MVFont.black(20)).foregroundStyle(uni.inkColor)
                    Text(store.isAheadOfShield(item) ? L10n.text("Chat e enquetes ao vivo · Escudo de Spoiler ativo") : event.question)
                        .font(MVFont.body(12, weight: 600)).foregroundStyle(uni.inkColor.opacity(0.85))
                }
                .padding(16)
            }
            HStack(spacing: 8) {
                Text(notifyMe ? L10n.text("✓ AVISANDO") : L10n.text("ME AVISE"))
                    .font(MVFont.bold(12))
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .foregroundStyle(notifyMe ? MV.C.paper : MV.C.ink)
                    .background(notifyMe ? MV.C.ink : MV.C.card)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .contentShape(Rectangle())
                    .onTapGesture { notifyMe.toggle() }
                Text(L10n.text("CONVIDAR"))
                    .font(MVFont.bold(12))
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .foregroundStyle(MV.C.ink)
                    .background(MV.C.card)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .contentShape(Rectangle())
            }
        }
        .comicCard(radius: MV.R.xl, shadow: MV.Shadow.m)
    }
}

private struct RoomRow: View {
    let room: Room
    @Environment(AppStore.self) private var store

    private var friendsHere: [User] {
        let pool = store.users.filter { store.follows.contains($0.id) }
        let count = Int(Logic.seed(room.itemID) % UInt32(max(pool.count, 1)))
        return Array(pool.prefix(min(count, 3)))
    }

    var body: some View {
        guard let item = store.item(room.itemID) else { return AnyView(EmptyView()) }
        let uni = store.universe(of: item)
        return AnyView(
            Button { store.push(.room(item.id)) } label: {
                HStack(spacing: 0) {
                    Rectangle().fill(uni.color).frame(width: 5)
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(item.title).font(MVFont.bold(14)).foregroundStyle(MV.C.ink).lineLimit(1)
                                if room.onlineCount > 0 {
                                    Text(L10n.text("AO VIVO")).font(MVFont.black(9)).foregroundStyle(MV.C.paper)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(MV.C.marvel).clipShape(Capsule())
                                }
                            }
                            Text(room.onlineCount > 0 ? "\(Logic.fmt(room.onlineCount)) online" : L10n.text("sem atividade agora"))
                                .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                            if !friendsHere.isEmpty {
                                HStack(spacing: -6) {
                                    ForEach(friendsHere) { friend in
                                        AvatarView(user: friend, size: 20, border: 1.5)
                                    }
                                }
                                Text(L10n.format("Você está em: %1$@", String(describing: store.roomProgress[room.itemID].map { "\($0 + 1)/\(room.segments.count)" } ?? L10n.text("não entrou"))))
                                    .font(MVFont.body(10, weight: 600)).foregroundStyle(MV.C.muted)
                            }
                        }
                        Spacer()
                        Text("→").foregroundStyle(MV.C.muted)
                    }
                    .padding(12)
                }
                .background(MV.C.card)
                .overlay(RoundedRectangle(cornerRadius: MV.R.lg).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.lg))
            }
            .buttonStyle(.plain)
        )
    }
}
