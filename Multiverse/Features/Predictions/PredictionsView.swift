import SwiftUI
import Combine

/// Previsões — recurso 1g.
struct PredictionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            if let event = store.predictionEvents.first {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    countdownCard(event: event)
                    VStack(spacing: 14) {
                        ForEach(Array(event.questions.enumerated()), id: \.element.id) { index, question in
                            QuestionCard(question: question, number: index + 1, total: event.questions.count)
                        }
                    }
                    leagueSection
                }
                .padding(.horizontal, MV.pad)
                .padding(.bottom, 24)
            }
        }
        .onReceive(timer) { now = $0 }
    }

    private var header: some View {
        HStack {
            Text("PREVISÕES").font(MVFont.display(30, width: 122)).foregroundStyle(MV.C.ink)
            Spacer()
            Text("\(Logic.fmt(store.predictionPoints)) PTS")
                .font(MVFont.black(13))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(MV.C.ink)
                .background(MV.C.wow)
                .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func countdownCard(event: PredictionEvent) -> some View {
        guard let uni = store.universe(event.uni) else { return AnyView(EmptyView()) }
        let remaining = max(0, Int(event.closesAt.timeIntervalSince(now)))
        let d = remaining / 86400, h = (remaining % 86400) / 3600, m = (remaining % 3600) / 60, s = remaining % 60

        return AnyView(
            ZStack(alignment: .topLeading) {
                MV.C.ink
                Halftone(color: MV.C.paper.opacity(0.1))
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(uni.name.uppercased()) · \(event.title.uppercased())").kicker(11).foregroundStyle(uni.color)
                    Text("AS APOSTAS FECHAM EM").font(MVFont.display(24, width: 118)).foregroundStyle(MV.C.paper)
                    HStack(spacing: 8) {
                        countUnit("\(d)", "DIAS")
                        countUnit(String(format: "%02d", h), "HORAS")
                        countUnit(String(format: "%02d", m), "MIN")
                        countUnit(String(format: "%02d", s), "SEG")
                    }
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
            .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .background(RoundedRectangle(cornerRadius: MV.R.xl).fill(uni.color).offset(x: MV.Shadow.m, y: MV.Shadow.m))
        )
    }

    private func countUnit(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(MVFont.black(30)).foregroundStyle(MV.C.paper).monospacedDigit()
            Text(label).font(MVFont.body(9, weight: 700)).foregroundStyle(MV.C.paper.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.paper.opacity(0.4), lineWidth: MV.stroke))
    }

    private var leagueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Liga dos amigos", trailing: "Ver tudo") {}
            HStack(spacing: 10) {
                ForEach(Array(store.predictionLeague().prefix(3).enumerated()), id: \.element.user.id) { index, entry in
                    VStack(spacing: 6) {
                        Text("#\(index + 1)").font(MVFont.black(14)).foregroundStyle(MV.C.ink)
                        AvatarView(user: entry.user, size: 40)
                        Text(entry.isMe ? "Você" : entry.user.name.components(separatedBy: " ").first ?? entry.user.name)
                            .font(MVFont.bold(12)).foregroundStyle(MV.C.ink)
                        Text("\(Logic.fmt(entry.points)) pts").font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(entry.isMe ? MV.C.wow : MV.C.card)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                }
            }
        }
    }
}

private struct QuestionCard: View {
    let question: PredictionQuestion
    let number: Int
    let total: Int
    @Environment(AppStore.self) private var store
    @State private var sliderValue: Double = 3.9

    var body: some View {
        let answer = store.predictionAnswer(for: question.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PERGUNTA \(number) DE \(total)").kicker(10).foregroundStyle(MV.C.muted)
                Spacer()
                Text("VALE \(question.points) PTS").font(MVFont.bold(10)).foregroundStyle(MV.C.muted)
            }
            Text(question.text.uppercased()).font(MVFont.black(16)).foregroundStyle(MV.C.ink)

            if let options = question.options {
                let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        optionButton(option: option, index: index, answer: answer)
                    }
                }
                if let answer, case .choice(let picked) = answer {
                    Text("Resultado revelado no lançamento. Você apostou em \(options[picked]).")
                        .font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                }
            } else {
                sliderRow(answer: answer)
            }
        }
        .padding(14)
        .comicCard(shadow: MV.Shadow.s)
    }

    private func optionButton(option: String, index: Int, answer: PredictionAnswer?) -> some View {
        let picked = { if case .choice(let i)? = answer { return i == index }; return false }()
        return Text((picked ? "✓ " : "") + option)
            .font(MVFont.bold(14))
            .frame(maxWidth: .infinity).frame(height: 46)
            .foregroundStyle(picked ? MV.C.ink : MV.C.ink)
            .background(picked ? MV.C.wow : MV.C.card)
            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
            .contentShape(Rectangle())
            .onTapGesture { store.submitPredictionChoice(questionID: question.id, optionIndex: index) }
    }

    @ViewBuilder
    private func sliderRow(answer: PredictionAnswer?) -> some View {
        HStack {
            Text("1").font(MVFont.bold(13)).foregroundStyle(MV.C.muted)
            Slider(value: $sliderValue, in: 1...5, step: 0.1) { editing in
                if !editing { store.submitPredictionSlider(questionID: question.id, value: sliderValue) }
            }
            .tint(MV.C.wow)
            Text("5").font(MVFont.bold(13)).foregroundStyle(MV.C.muted)
            Text(String(format: "%.1f", sliderValue)).font(MVFont.black(15)).foregroundStyle(MV.C.ink).frame(width: 36)
        }
        .onAppear {
            if case .slider(let v)? = answer { sliderValue = v } else { sliderValue = 3.9 }
        }
    }
}
