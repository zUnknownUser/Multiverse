import SwiftUI
import Combine

private struct FloatingSticker: Identifiable {
    let id = UUID()
    let text: String
    let x: CGFloat
    let y: CGFloat
    let rotation: Double
}

private struct LiveChatLine: Identifiable {
    let id = UUID()
    let userID: String
    let text: String
}

/// "Estreia ao vivo" — recurso 5f. Tela em Modo Noir com contador, enquete relâmpago,
/// onomatopeias flutuantes e chat ao vivo simulado.
struct LivePremiereView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var elapsedSeconds = 0
    @State private var stickers: [FloatingSticker] = []
    @State private var chatLines: [LiveChatLine] = []
    @State private var comment = ""
    @State private var pollSecondsLeft = 15
    @State private var pollVote: Int?
    @State private var revealedAnyway = false

    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let chatTimer = Timer.publish(every: 2.4, on: .main, in: .common).autoconnect()
    private let stickerTimer = Timer.publish(every: 3.1, on: .main, in: .common).autoconnect()

    private let sampleChatLines = [
        "NÃO ACREDITO NISSO", "KRAK! essa cena", "alguém mais chorando?", "essa trilha sonora ㅤ",
        "voltou a ligação da era 3!!", "ok isso foi surpreendente", "reassistindo já no fim disso"
    ]

    var body: some View {
        ZStack {
            Color(hex: "#0B0B10").ignoresSafeArea()

            if let event = store.liveEvent, let item = store.item(event.itemID), store.isAheadOfShield(item), !revealedAnyway {
                shieldedBlock(item: item)
            } else if let event = store.liveEvent, let item = store.item(event.itemID) {
                VStack(spacing: 0) {
                    topBar(event: event)
                    Spacer(minLength: 0)
                    pollCard(event: event)
                        .padding(.horizontal, MV.pad)
                    Spacer(minLength: 0)
                    liveChat
                    reactionRow(event: event)
                    commentField
                }
                .padding(.bottom, 10)

                ForEach(stickers) { sticker in
                    Text(sticker.text)
                        .font(MVFont.black(22))
                        .foregroundStyle(Color(hex: item.id.hasPrefix("d-") ? "#E23636" : (item.id.hasPrefix("m-") ? "#ED1D24" : "#00AEEF")))
                        .rotationEffect(.degrees(sticker.rotation))
                        .position(x: sticker.x, y: sticker.y)
                        .transition(.opacity)
                }
            } else {
                Text("Nenhuma estreia ao vivo agora.").font(MVFont.bold(14)).foregroundStyle(.white)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(clockTimer) { _ in elapsedSeconds += 1 }
        .onReceive(chatTimer) { _ in addChatLine() }
        .onReceive(stickerTimer) { _ in addSticker() }
        .task {
            guard store.liveEvent != nil else { return }
            startPollCountdown()
        }
    }

    private func shieldedBlock(item: Item) -> some View {
        VStack(spacing: 14) {
            HStack {
                Button { dismiss() } label: {
                    Text("SAIR").font(MVFont.bold(12)).foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            Spacer()
            Text("◆ ESCUDO DE SPOILER").font(MVFont.black(11)).tracking(0.4).foregroundStyle(.black)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(MV.C.dc).clipShape(Capsule())
            Text("A estreia de \(item.title) está à sua frente na timeline.")
                .font(MVFont.bold(16)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Mostrar mesmo assim") { revealedAnyway = true }
                .font(MVFont.bold(13)).underline().foregroundStyle(.white)
                .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, MV.pad)
        .padding(.top, 12)
    }

    private func startPollCountdown() {
        Task {
            while pollSecondsLeft > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if pollSecondsLeft > 0 { pollSecondsLeft -= 1 }
            }
        }
    }

    private var elapsedLabel: String {
        let h = elapsedSeconds / 3600, m = (elapsedSeconds % 3600) / 60, s = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d de filme", h, m, s)
    }

    @ViewBuilder
    private func topBar(event: LiveEvent) -> some View {
        HStack {
            Button { dismiss() } label: {
                Text("SAIR").font(MVFont.bold(12)).foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 6) {
                Text("● AO VIVO").font(MVFont.black(11)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(MV.C.marvel).clipShape(Capsule())
                Text("\(Logic.fmt(event.viewerCount)) assistindo").font(MVFont.body(11, weight: 600)).foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, MV.pad)
        .padding(.top, 12)

        Text(elapsedLabel)
            .font(MVFont.black(13))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.top, 4)
            .frame(maxWidth: .infinity)
    }

    private func pollCard(event: LiveEvent) -> some View {
        let revealed = pollSecondsLeft == 0 || pollVote != nil
        let simYes = 40 + Int(Logic.seed(event.id + "y") % 35)
        let simNo = 100 - simYes
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("⚡ RELÂMPAGO").font(MVFont.black(11)).foregroundStyle(.black)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(MV.C.wow).clipShape(Capsule())
                Spacer()
                if !revealed {
                    Text("\(pollSecondsLeft)s").font(MVFont.black(13)).foregroundStyle(.white.opacity(0.7))
                }
            }
            Text(event.question).font(MVFont.bold(15)).foregroundStyle(.white)
            HStack(spacing: 8) {
                pollOption(label: "SIM", percent: simYes, index: 0, revealed: revealed)
                pollOption(label: "NÃO", percent: simNo, index: 1, revealed: revealed)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: MV.R.lg).strokeBorder(.white.opacity(0.3), lineWidth: MV.stroke))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.lg))
    }

    private func pollOption(label: String, percent: Int, index: Int, revealed: Bool) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: MV.R.sm).fill(Color.white.opacity(0.12))
            if revealed {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: MV.R.sm)
                        .fill(pollVote == index ? MV.C.wow.opacity(0.8) : Color.white.opacity(0.25))
                        .frame(width: geo.size.width * CGFloat(percent) / 100)
                }
            }
            HStack {
                Text(label).font(MVFont.bold(13)).foregroundStyle(.white)
                Spacer()
                if revealed { Text("\(percent)%").font(MVFont.black(12)).foregroundStyle(.white) }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture { if pollVote == nil { pollVote = index } }
    }

    private var liveChat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(chatLines) { line in
                        if let user = store.user(line.userID) {
                            (Text("\(user.name): ").font(MVFont.bold(12)).foregroundStyle(.white.opacity(0.9))
                                + Text(line.text).font(MVFont.body(12, weight: 500)).foregroundStyle(.white.opacity(0.75)))
                                .id(line.id)
                        }
                    }
                }
                .padding(.horizontal, MV.pad)
                .padding(.vertical, 8)
            }
            .frame(height: 140)
            .onChange(of: chatLines.count) { _, _ in
                if let last = chatLines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private func reactionRow(event: LiveEvent) -> some View {
        let key = "live:\(event.id)"
        return HStack(spacing: 10) {
            ForEach(ReactionType.allCases, id: \.self) { type in
                Text(type.rawValue)
                    .font(MVFont.black(14))
                    .foregroundStyle(type.textColor)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(type.color)
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .burstOnTap(type.rawValue, color: type.color, when: store.userReaction(for: key) != type) {
                        store.setReaction(type, for: key)
                    }
            }
        }
        .padding(.horizontal, MV.pad)
        .padding(.top, 8)
    }

    private var commentField: some View {
        HStack(spacing: 8) {
            TextField("Comentar ao vivo…", text: $comment)
                .font(MVFont.body(13, weight: 500))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
                .onSubmit {
                    guard !comment.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    chatLines.append(LiveChatLine(userID: store.meID, text: comment))
                    comment = ""
                }
        }
        .padding(.horizontal, MV.pad)
        .padding(.top, 8)
    }

    private func addChatLine() {
        let others = store.users.filter { $0.id != store.meID }
        guard let user = others.randomElement(), let text = sampleChatLines.randomElement() else { return }
        chatLines.append(LiveChatLine(userID: user.id, text: text))
        if chatLines.count > 40 { chatLines.removeFirst(chatLines.count - 40) }
    }

    private func addSticker() {
        let symbols = ["POW!", "ZAP!", "KRAK!", "HEH"]
        guard let text = symbols.randomElement() else { return }
        let sticker = FloatingSticker(
            text: text,
            x: CGFloat.random(in: 40...330),
            y: CGFloat.random(in: 150...420),
            rotation: Double.random(in: -18...18)
        )
        withAnimation { stickers.append(sticker) }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { stickers.removeAll { $0.id == sticker.id } }
        }
    }
}
