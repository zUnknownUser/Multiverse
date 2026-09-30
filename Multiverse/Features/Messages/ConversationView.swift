import SwiftUI

/// "Conversa com cartas" — recurso 5c.
struct ConversationView: View {
    let userID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var showingSendCard = false

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            if let user = store.user(userID) {
                VStack(alignment: .leading, spacing: 14) {
                    header(user: user).padding(.horizontal, MV.pad)
                    messagesList(user: user).padding(.horizontal, MV.pad)
                }
                .padding(.bottom, 90)
                .task { store.openConversation(with: userID); await store.loadMessages(with: userID) }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .sheet(isPresented: $showingSendCard) {
            AttachCardSheet(userID: userID)
        }
    }

    @ViewBuilder
    private func header(user: User) -> some View {
        HStack(spacing: 10) {
            AvatarView(user: user, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name).font(MVFont.bold(16)).foregroundStyle(MV.C.ink)
                let pct = 40 + Int(Logic.seed(user.id) % 55)
                Text("\(pct)% de afinidade · online agora").font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
            }
            Spacer()
            Button { store.showingChallengeUserID = user.id } label: {
                Text("DESAFIAR")
                    .font(MVFont.bold(11))
                    .padding(.horizontal, 12).frame(height: 34)
                    .foregroundStyle(MV.C.ink)
                    .background(MV.C.wow)
                    .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func messagesList(user: User) -> some View {
        VStack(spacing: 12) {
            ForEach(store.messages(with: userID)) { message in
                MessageBubble(message: message, otherUser: user)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            Button { showingSendCard = true } label: {
                Text("+")
                    .font(MVFont.black(20))
                    .foregroundStyle(MV.C.ink)
                    .frame(width: 40, height: 40)
                    .background(MV.C.card)
                    .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            TextField("Escreva algo…", text: $draft)
                .font(MVFont.body(14, weight: 500))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(MV.C.card)
                .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(Capsule())
                .onSubmit(send)

            Text("ENVIAR")
                .font(MVFont.bold(12))
                .padding(.horizontal, 16).frame(height: 44)
                .foregroundStyle(MV.C.paper)
                .background(MV.C.ink)
                .clipShape(Capsule())
                .contentShape(Rectangle())
                .onTapGesture(perform: send)
        }
        .padding(.horizontal, MV.pad)
        .padding(.vertical, 10)
        .background(MV.C.paper)
        .overlay(alignment: .top) { Rectangle().fill(MV.C.ink).frame(height: MV.stroke) }
    }

    private func send() {
        store.sendMessage(to: userID, text: draft)
        draft = ""
    }
}

private struct MessageBubble: View {
    let message: Message
    let otherUser: User
    @Environment(AppStore.self) private var store

    private var isMe: Bool { message.senderID == store.meID }

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 40) }
            content
            if !isMe { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .text:
            Text(message.text ?? "")
                .font(MVFont.body(14, weight: 500))
                .foregroundStyle(isMe ? MV.C.paper : MV.C.ink)
                .padding(12)
                .background(isMe ? MV.C.ink : MV.C.card)
                .overlay(RoundedRectangle(cornerRadius: MV.R.lg).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.lg))
        case .workCard:
            if store.isShieldedMessage(message) {
                shieldedCard
            } else if let itemID = message.itemID, let item = store.item(itemID) {
                workCard(item: item)
            }
        case .duelChallenge:
            if let payload = message.duelChallenge {
                duelCard(payload: payload)
            }
        }
    }

    private var shieldedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("◆ ESCUDO DE SPOILER").font(MVFont.black(10)).tracking(0.4).foregroundStyle(MV.C.card)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(MV.C.dc)
                .overlay(RoundedRectangle(cornerRadius: MV.R.xs).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.xs))
            Text("\(otherUser.name) mandou uma carta sobre algo à sua frente.")
                .font(MVFont.body(13, weight: 600)).foregroundStyle(MV.C.ink)
            Button("Mostrar mesmo assim") { store.revealSpoiler(message.id) }
                .font(MVFont.bold(12)).underline().foregroundStyle(MV.C.ink)
                .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 220, alignment: .leading)
        .background(MV.C.dc.opacity(0.3))
        .overlay(RoundedRectangle(cornerRadius: MV.R.lg).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.lg))
    }

    private func workCard(item: Item) -> some View {
        let uni = store.universe(of: item)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                PosterView(item: item, universe: uni, width: 56, height: 84, titleSize: 10, shadow: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(MVFont.bold(13)).foregroundStyle(MV.C.ink).lineLimit(2)
                    Text(String(format: "%.1f ★", item.avg)).font(MVFont.black(13)).foregroundStyle(MV.C.ink)
                }
            }
            if let text = message.text, !text.isEmpty {
                Text(text).font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.ink)
            }
            HStack(spacing: 6) {
                let wanted = store.isWanted(item.id)
                Text(wanted ? "✓ NA LISTA" : "+ QUERO")
                    .font(MVFont.bold(10))
                    .padding(.horizontal, 10).frame(height: 30)
                    .foregroundStyle(wanted ? MV.C.paper : MV.C.ink)
                    .background(wanted ? MV.C.ink : MV.C.paper)
                    .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(Capsule())
                    .contentShape(Rectangle())
                    .onTapGesture { store.toggleWanted(item.id) }
                Text("VER →")
                    .font(MVFont.bold(10))
                    .padding(.horizontal, 10).frame(height: 30)
                    .foregroundStyle(MV.C.ink)
                    .background(MV.C.paper)
                    .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(Capsule())
                    .contentShape(Rectangle())
                    .onTapGesture { store.push(.item(item.id)) }
            }
        }
        .padding(12)
        .frame(width: 220, alignment: .leading)
        .background(uni.color.opacity(0.25))
        .overlay(RoundedRectangle(cornerRadius: MV.R.lg).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.lg))
    }

    private func duelCard(payload: DuelChallengePayload) -> some View {
        let itemA = store.item(payload.itemAID)
        let itemB = store.item(payload.itemBID)
        let responded = payload.responderChoice != nil
        return VStack(alignment: .leading, spacing: 8) {
            Text("DUELO · \(payload.wager)").kicker(9).foregroundStyle(MV.C.muted)
            Text(payload.question).font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
            HStack(spacing: 6) {
                duelSide(title: itemA?.title ?? "?", color: MV.C.marvel, chosen: payload.chooserChoice == 0, responded: payload.responderChoice == 0)
                Text("VS").font(MVFont.black(11)).foregroundStyle(MV.C.muted)
                duelSide(title: itemB?.title ?? "?", color: MV.C.dc, chosen: payload.chooserChoice == 1, responded: payload.responderChoice == 1)
            }
            if !isMe && !responded {
                HStack(spacing: 6) {
                    Text("ESCOLHER A")
                        .font(MVFont.bold(10)).padding(.horizontal, 8).frame(height: 28)
                        .foregroundStyle(MV.C.paper).background(MV.C.marvel).clipShape(Capsule())
                        .contentShape(Rectangle())
                        .onTapGesture { store.respondToDuelChallenge(messageID: message.id, in: message.conversationID, choice: 0) }
                    Text("ESCOLHER B")
                        .font(MVFont.bold(10)).padding(.horizontal, 8).frame(height: 28)
                        .foregroundStyle(MV.C.paper).background(MV.C.dc).clipShape(Capsule())
                        .contentShape(Rectangle())
                        .onTapGesture { store.respondToDuelChallenge(messageID: message.id, in: message.conversationID, choice: 1) }
                }
            } else if responded {
                Text("Respondido · KRAK!").font(MVFont.bold(11)).foregroundStyle(MV.C.muted)
            }
        }
        .padding(12)
        .frame(width: 230, alignment: .leading)
        .background(MV.C.card)
        .overlay(RoundedRectangle(cornerRadius: MV.R.lg).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.lg))
    }

    private func duelSide(title: String, color: Color, chosen: Bool, responded: Bool) -> some View {
        Text(title)
            .font(MVFont.bold(10))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(6)
            .foregroundStyle(MV.C.ink)
            .background((chosen || responded) ? color.opacity(0.5) : MV.C.paper)
            .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.sm))
    }
}
