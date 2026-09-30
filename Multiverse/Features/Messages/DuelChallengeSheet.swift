import SwiftUI

private enum ChallengeKind: String, CaseIterable { case duelo = "Duelo", previsao = "Previsão", quiz = "Quiz de Lore" }

private let wagerOptions = ["Café", "Emoji de perdedor", "Assistir o que o outro escolher", "Nada, só orgulho"]

/// "Chamar pro duelo" — recurso 5g. Aberta do perfil ou do card de Duelo da Home.
struct DuelChallengeSheet: View {
    let userID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ChallengeKind = .duelo
    @State private var question = ""
    @State private var itemAID = ""
    @State private var itemBID = ""
    @State private var wager = wagerOptions[0]
    @State private var myChoice = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let user = store.user(userID) {
                        Text("DESAFIAR \(user.name.uppercased())")
                            .font(MVFont.display(24, width: 115)).foregroundStyle(MV.C.ink)
                    }

                    kindPicker

                    Text("PERGUNTA").kicker(11).foregroundStyle(MV.C.muted)
                    TextField("Ex.: qual filme é melhor?", text: $question)
                        .font(MVFont.body(14, weight: 500))
                        .padding(12)
                        .background(MV.C.card)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))

                    vsRow

                    Text("APOSTA").kicker(11).foregroundStyle(MV.C.muted)
                    WrapPills(options: wagerOptions, selected: wager) { wager = $0 }

                    Text("SEU LADO").kicker(11).foregroundStyle(MV.C.muted)
                    HStack(spacing: 8) {
                        sideChoice(label: itemTitle(itemAID) ?? "Lado A", color: MV.C.marvel, index: 0)
                        sideChoice(label: itemTitle(itemBID) ?? "Lado B", color: MV.C.dc, index: 1)
                    }
                }
                .padding(MV.pad)
            }
            .background(MV.C.paper)
            .navigationTitle("Chamar pro duelo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { sendBar }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        guard itemAID.isEmpty, itemBID.isEmpty else { return }
        let duel = store.currentDuel
        itemAID = duel.a
        itemBID = duel.b
        question = duel.question
    }

    private func itemTitle(_ id: String) -> String? { store.item(id)?.title }

    private var kindPicker: some View {
        HStack(spacing: 0) {
            ForEach(ChallengeKind.allCases, id: \.self) { k in
                let selected = kind == k
                Text(k.rawValue.uppercased())
                    .font(MVFont.bold(11))
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .foregroundStyle(selected ? MV.C.paper : MV.C.ink)
                    .background(selected ? MV.C.ink : MV.C.card)
                    .contentShape(Rectangle())
                    .onTapGesture { kind = k }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
    }

    private var vsRow: some View {
        HStack(spacing: 10) {
            itemPicker(selection: $itemAID, color: MV.C.marvel)
            Text("VS").font(MVFont.black(13)).foregroundStyle(MV.C.muted)
            itemPicker(selection: $itemBID, color: MV.C.dc)
        }
    }

    private func itemPicker(selection: Binding<String>, color: Color) -> some View {
        Menu {
            ForEach(store.items.prefix(60)) { item in
                Button(item.title) { selection.wrappedValue = item.id }
            }
        } label: {
            VStack(spacing: 4) {
                if let item = store.item(selection.wrappedValue) {
                    Text(item.title).font(MVFont.bold(12)).lineLimit(2).multilineTextAlignment(.center)
                } else {
                    Text("Escolher item").font(MVFont.bold(12))
                }
            }
            .foregroundStyle(MV.C.ink)
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(8)
            .background(color.opacity(0.25))
            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        }
    }

    private func sideChoice(label: String, color: Color, index: Int) -> some View {
        Text(label)
            .font(MVFont.bold(12))
            .lineLimit(1)
            .frame(maxWidth: .infinity).frame(height: 44)
            .foregroundStyle(MV.C.ink)
            .background(myChoice == index ? color : MV.C.card)
            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
            .contentShape(Rectangle())
            .onTapGesture { myChoice = index }
    }

    private var sendBar: some View {
        Text("MANDAR DESAFIO · KRAK!")
            .font(MVFont.bold(14))
            .frame(maxWidth: .infinity).frame(height: 50)
            .foregroundStyle(MV.C.paper)
            .background(question.trimmingCharacters(in: .whitespaces).isEmpty || itemAID.isEmpty || itemBID.isEmpty ? MV.C.muted : MV.C.ink)
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
            .padding(MV.pad)
            .background(MV.C.paper)
            .overlay(alignment: .top) { Rectangle().fill(MV.C.ink).frame(height: MV.stroke) }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !question.trimmingCharacters(in: .whitespaces).isEmpty, !itemAID.isEmpty, !itemBID.isEmpty else { return }
                store.sendDuelChallenge(to: userID, itemAID: itemAID, itemBID: itemBID, question: question, wager: wager, myChoice: myChoice)
                dismiss()
            }
    }
}

private struct WrapPills: View {
    let options: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Text(option)
                        .font(MVFont.bold(12))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(selected == option ? MV.C.paper : MV.C.ink)
                        .background(selected == option ? MV.C.ink : MV.C.card)
                        .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(Capsule())
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(option) }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}
