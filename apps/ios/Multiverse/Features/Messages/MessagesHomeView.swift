import SwiftUI

private enum MessagesTab: String, CaseIterable { case amigos = "Amigos", clubes = "Clubes", pedidos = "Pedidos" }

/// "Mensagens" — recurso 5b.
struct MessagesHomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var tab: MessagesTab = .amigos
    @State private var showingNewMessage = false

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(L10n.text("MENSAGENS")).font(MVFont.display(30, width: 122)).foregroundStyle(MV.C.ink)
                    Spacer()
                    Button { showingNewMessage = true } label: {
                        Text("✎").font(.system(size: 18, weight: .bold))
                            .foregroundStyle(MV.C.paper)
                            .frame(width: 40, height: 40)
                            .background(MV.C.ink)
                            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    }
                    .buttonStyle(.plain)
                }

                if !store.rooms.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.text("SALAS AO VIVO AGORA")).kicker(11).foregroundStyle(MV.C.muted)
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(liveRoomItems) { item in
                                    liveRoomCard(item: item)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                tabPicker

                switch tab {
                case .amigos: conversationList(store.friendConversations, empty: L10n.text("Nenhuma conversa ainda."))
                case .clubes: clubsConversationsPlaceholder
                case .pedidos: conversationList(store.requestConversations, empty: L10n.text("Nenhum pedido novo."))
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showingNewMessage) {
            FriendPickerSheet(title: L10n.text("Nova conversa")) { store.push(.conversation($0)) }
        }
    }

    private var liveRoomItems: [Item] {
        store.rooms.compactMap { store.item($0.itemID) }.filter { !store.isAheadOfShield($0) }
    }

    private func liveRoomCard(item: Item) -> some View {
        let uni = store.universe(of: item)
        let online = store.room(for: item.id)?.onlineCount ?? 0
        return Button { store.push(.room(item.id)) } label: {
            ZStack(alignment: .topLeading) {
                uni.color
                Halftone(color: uni.inkColor.opacity(0.18))
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("● AO VIVO"))
                        .font(MVFont.bold(10))
                        .foregroundStyle(MV.C.paper)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(MV.C.marvel)
                        .clipShape(Capsule())
                    Spacer(minLength: 0)
                    Text(item.title.uppercased()).font(MVFont.black(15)).foregroundStyle(uni.inkColor).lineLimit(2)
                    Text(L10n.format("%1$@ na sala", String(describing: Logic.fmt(online)))).font(MVFont.bold(11)).foregroundStyle(uni.inkColor.opacity(0.85))
                }
                .padding(12)
            }
            .frame(width: 160, height: 130)
            .comicCard(bg: uni.color, radius: MV.R.xl, shadow: MV.Shadow.s)
        }
        .buttonStyle(.plain)
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(MessagesTab.allCases, id: \.self) { t in
                let selected = tab == t
                let label = t == .pedidos && !store.requestConversations.isEmpty ? "\(L10n.text(t.rawValue)) (\(store.requestConversations.count))" : L10n.text(t.rawValue)
                Text(label.uppercased())
                    .font(MVFont.bold(12))
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .foregroundStyle(selected ? MV.C.paper : MV.C.ink)
                    .background(selected ? MV.C.ink : MV.C.card)
                    .contentShape(Rectangle())
                    .onTapGesture { tab = t }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
    }

    @ViewBuilder
    private func conversationList(_ list: [Conversation], empty: String) -> some View {
        if list.isEmpty {
            Text(empty).font(MVFont.body(14)).foregroundStyle(MV.C.muted).padding(.top, 12)
        } else {
            VStack(spacing: 0) {
                ForEach(list) { convo in
                    ConversationRow(conversation: convo)
                    Divider().overlay(MV.C.divider)
                }
            }
        }
    }

    private var clubsConversationsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(store.clubs) { club in
                Button { store.push(.club(club.id)) } label: {
                    HStack {
                        Text(club.name).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                        Spacer()
                        Text("→").foregroundStyle(MV.C.muted)
                    }
                    .padding(12)
                    .comicCard(shadow: MV.Shadow.s)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    @Environment(AppStore.self) private var store

    var body: some View {
        guard let user = store.user(conversation.userID) else { return AnyView(EmptyView()) }
        return AnyView(
            Button { store.push(.conversation(user.id)) } label: {
                HStack(spacing: 12) {
                    AvatarView(user: user, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.name).font(MVFont.bold(15)).foregroundStyle(MV.C.ink)
                        Text(conversation.lastPreview).font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.muted).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(conversation.lastWhen).font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                        if conversation.unreadCount > 0 {
                            Text("\(conversation.unreadCount)")
                                .font(MVFont.black(11))
                                .foregroundStyle(MV.C.paper)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(MV.C.marvel))
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        )
    }
}
