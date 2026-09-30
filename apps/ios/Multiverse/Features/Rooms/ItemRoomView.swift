import SwiftUI

/// "Sala da obra" — recurso 5e. Chat por trecho (era/capítulo), com o Escudo de Spoiler
/// escondendo tudo além de onde o usuário está.
struct ItemRoomView: View {
    let itemID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var segmentIndex = 0
    @State private var draft = ""

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            if let item = store.item(itemID), let room = store.room(for: itemID) {
                let uni = store.universe(of: item)
                VStack(alignment: .leading, spacing: 14) {
                    header(item: item, uni: uni, room: room).padding(.horizontal, MV.pad)
                    segmentPicker(room: room).padding(.horizontal, MV.pad)
                    if let theory = pinnedTheory(uni: uni) {
                        pinnedTheoryRow(theory: theory).padding(.horizontal, MV.pad)
                    }
                    messagesList(room: room).padding(.horizontal, MV.pad)
                }
                .padding(.bottom, 90)
                .task { segmentIndex = min(progress(room: room), room.segments.count - 1); await store.loadRoomMessages(itemID: itemID) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let room = store.room(for: itemID) {
                replyBar(room: room)
            }
        }
    }

    private func progress(room: Room) -> Int { store.roomProgress[itemID] ?? 0 }

    private func pinnedTheory(uni: Universe) -> Theory? {
        store.theories.first { $0.uni == uni.id }
    }

    @ViewBuilder
    private func header(item: Item, uni: Universe, room: Room) -> some View {
        HStack(spacing: 12) {
            PosterView(item: item, universe: uni, width: 50, height: 75, titleSize: 9, shadow: MV.Shadow.s)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(MVFont.bold(16)).foregroundStyle(MV.C.ink)
                HStack(spacing: 6) {
                    Text(L10n.text("● AO VIVO")).font(MVFont.black(10)).foregroundStyle(MV.C.paper)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(MV.C.marvel).clipShape(Capsule())
                    Text("\(Logic.fmt(room.onlineCount)) online").font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func segmentPicker(room: Room) -> some View {
        let myProgress = progress(room: room)
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(room.segments.enumerated()), id: \.offset) { idx, name in
                    let done = idx < myProgress
                    let locked = idx > myProgress
                    let selected = idx == segmentIndex
                    HStack(spacing: 4) {
                        Text(done ? "✓" : (locked ? "◆" : "●")).font(MVFont.bold(11))
                        Text(name.uppercased()).font(MVFont.bold(11))
                    }
                    .padding(.horizontal, 12).frame(height: 38)
                    .foregroundStyle(selected ? MV.C.paper : (locked ? MV.C.muted : MV.C.ink))
                    .background(selected ? MV.C.ink : MV.C.card)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .contentShape(Rectangle())
                    .onTapGesture { if !locked { segmentIndex = idx } }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func pinnedTheoryRow(theory: Theory) -> some View {
        Button { store.push(.theoryDetail(theory.id)) } label: {
            HStack(alignment: .top, spacing: 8) {
                Text("📌").font(.system(size: 14))
                Text(theory.text).font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.ink).lineLimit(2)
                Spacer()
            }
            .padding(10)
            .background(MV.C.wow.opacity(0.25))
            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func messagesList(room: Room) -> some View {
        let myProgress = progress(room: room)
        let locked = segmentIndex > myProgress
        if locked {
            lockedBlock
        } else {
            let messages = store.roomMessagesFor(itemID: itemID, segment: segmentIndex)
            VStack(spacing: 12) {
                if messages.isEmpty {
                    Text(L10n.text("Nenhuma mensagem aqui ainda.")).font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.muted)
                }
                ForEach(messages) { message in
                    RoomMessageBubble(message: message)
                }
            }
            if segmentIndex == myProgress, myProgress < room.segments.count - 1 {
                advanceButton(room: room, myProgress: myProgress)
            }
        }
    }

    private var lockedBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("◆ ESCUDO")).font(MVFont.black(10)).tracking(0.4).foregroundStyle(MV.C.card)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(MV.C.dc)
                .overlay(RoundedRectangle(cornerRadius: MV.R.xs).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.xs))
            Text(L10n.text("Esse trecho está à sua frente. Avance na sala pra desbloquear a conversa."))
                .font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MV.C.dc.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
    }

    private func advanceButton(room: Room, myProgress: Int) -> some View {
        Button(L10n.format("Já cheguei em %1$@", String(describing: room.segments[myProgress + 1].lowercased()))) {
            store.setRoomProgress(itemID: itemID, segment: myProgress + 1)
        }
        .font(MVFont.bold(13)).underline().foregroundStyle(MV.C.ink)
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func replyBar(room: Room) -> some View {
        let myProgress = progress(room: room)
        let locked = segmentIndex > myProgress
        return HStack(spacing: 8) {
            TextField(locked ? L10n.text("Trecho bloqueado") : L10n.format("Comentar sobre %1$@…", String(describing: room.segments[segmentIndex])), text: $draft)
                .font(MVFont.body(14, weight: 500))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(MV.C.card)
                .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(Capsule())
                .disabled(locked)
                .onSubmit(send)
            Text(L10n.text("ENVIAR"))
                .font(MVFont.bold(12))
                .padding(.horizontal, 16).frame(height: 44)
                .foregroundStyle(MV.C.paper)
                .background(locked ? MV.C.muted : MV.C.ink)
                .clipShape(Capsule())
                .contentShape(Rectangle())
                .onTapGesture { if !locked { send() } }
        }
        .padding(.horizontal, MV.pad)
        .padding(.vertical, 10)
        .background(MV.C.paper)
        .overlay(alignment: .top) { Rectangle().fill(MV.C.ink).frame(height: MV.stroke) }
    }

    private func send() {
        store.postRoomMessage(itemID: itemID, segment: segmentIndex, text: draft)
        draft = ""
    }
}

private struct RoomMessageBubble: View {
    let message: RoomMessage
    @Environment(AppStore.self) private var store
    @State private var showReactionBar = false

    private var reactionKey: String { "room:\(message.id)" }

    var body: some View {
        guard let user = store.user(message.userID) else { return AnyView(EmptyView()) }
        let isMe = user.id == store.meID
        return AnyView(
            HStack {
                if isMe { Spacer(minLength: 40) }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        if !isMe { AvatarView(user: user, size: 28) }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(isMe ? L10n.text("Você") : user.name).font(MVFont.bold(12)).foregroundStyle(MV.C.ink)
                                Spacer()
                                Text(message.when).font(MVFont.body(10, weight: 600)).foregroundStyle(MV.C.muted)
                            }
                            Text(message.text).font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.ink)
                        }
                    }
                    .padding(10)
                    .background(isMe ? MV.C.wow : MV.C.card)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.lg).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.lg))
                    .reactionBar(isPresented: $showReactionBar, onReact: { store.setReaction($0, for: reactionKey) })

                    ReactionPillsRow(reviewID: reactionKey)
                }
                if !isMe { Spacer(minLength: 40) }
            }
        )
    }
}
