import SwiftUI

/// Bottom sheet de registro — aberto pelo botão + da tab bar ou por "Registrar"/"Avaliar"
/// numa Obra. `AppStore.logDraft` guia se mostramos a grade de escolha ou o formulário.
struct LogSheetView: View {
    @Environment(AppStore.self) private var store
    @Environment(BurstCenter.self) private var burst
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(MV.C.ink).frame(width: 44, height: 5).padding(.top, 10).padding(.bottom, 14)

            ScrollView {
                if store.logDraft?.itemID == nil {
                    PickItemContent()
                } else {
                    LogFormContent(onPublished: { dismiss() })
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(MV.C.paper)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 20))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 20)
                .strokeBorder(MV.C.ink, lineWidth: MV.stroke)
        }
        .presentationDetents([.fraction(0.92)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
    }
}

private struct PickItemContent: View {
    @Environment(AppStore.self) private var store
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("O QUE VOCÊ VIU, LEU OU JOGOU?")
                .font(MVFont.section(18)).foregroundStyle(MV.C.ink)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(StaticContent.logQuickPickIDs, id: \.self) { id in
                    if let item = store.item(id) {
                        Button { store.setLogItem(item.id) } label: {
                            PosterView(item: item, universe: store.universe(of: item), width: 104, height: 156, titleSize: 11)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, MV.pad)
        .padding(.bottom, 24)
    }
}

private struct LogFormContent: View {
    @Environment(AppStore.self) private var store
    let onPublished: () -> Void

    var body: some View {
        if let itemID = store.logDraft?.itemID, let item = store.item(itemID) {
            let uni = store.universe(of: item)
            let rating = store.logDraft?.rating ?? 0

            VStack(alignment: .leading, spacing: 18) {
                header(item: item, uni: uni)
                ratingPicker(uni: uni, rating: rating)
                togglePills
                reviewField
                Text("Vai aparecer no feed dos seus 312 seguidores e na página de \(item.title).")
                    .font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                publishButton(item: item, uni: uni)
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func header(item: Item, uni: Universe) -> some View {
        HStack(spacing: 12) {
            PosterView(item: item, universe: uni, width: 52, height: 78, titleSize: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Logic.verb(item.type)) · Hoje, 29 set").font(MVFont.body(11, weight: 700)).foregroundStyle(MV.C.muted)
                Text(item.title).font(MVFont.bold(17)).foregroundStyle(MV.C.ink)
                Text("\(uni.name) · \(item.type)").font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func ratingPicker(uni: Universe, rating: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTA").kicker(11).foregroundStyle(MV.C.muted)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { n in
                    let full = rating >= Double(n)
                    let half = rating == Double(n) - 0.5
                    Text(half ? "½" : "★")
                        .font(MVFont.black(22))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .foregroundStyle(full || half ? uni.inkColor : MV.C.ink.opacity(0.25))
                        .background(full || half ? uni.color : MV.C.card)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                        .contentShape(Rectangle())
                        .onTapGesture { store.setLogRating(n) }
                }
            }
            Text(rating > 0 ? Logic.starHint(rating) : "Toque de novo pra meia estrela")
                .font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.muted)
        }
    }

    private var togglePills: some View {
        HStack(spacing: 8) {
            pill("♥ Curti", isOn: store.logDraft?.liked ?? false) { toggle(\.liked) }
            pill("↻ Revisitei", isOn: store.logDraft?.rewatch ?? false) { toggle(\.rewatch) }
            pill("⚠ Contém spoiler", isOn: store.logDraft?.spoiler ?? false) { toggle(\.spoiler) }
        }
    }

    private func pill(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Text(title)
            .font(MVFont.bold(12))
            .padding(.horizontal, 11).padding(.vertical, 8)
            .foregroundStyle(isOn ? MV.C.paper : MV.C.ink)
            .background(isOn ? MV.C.ink : MV.C.card)
            .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(Capsule())
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    private func toggle(_ keyPath: WritableKeyPath<LogDraft, Bool>) {
        guard var draft = store.logDraft else { return }
        draft[keyPath: keyPath].toggle()
        store.logDraft = draft
    }

    private var reviewField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUA REVIEW").kicker(11).foregroundStyle(MV.C.muted)
            TextField(
                "Escreva sua review… teorias de cânone são bem-vindas.",
                text: Binding(get: { store.logDraft?.text ?? "" }, set: { text in
                    guard var draft = store.logDraft else { return }
                    draft.text = text
                    store.logDraft = draft
                }),
                axis: .vertical
            )
            .font(MVFont.body(14, weight: 500))
            .lineLimit(4...6)
            .padding(12)
            .frame(minHeight: 92, alignment: .topLeading)
            .background(MV.C.card)
            .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
        }
    }

    private func publishButton(item: Item, uni: Universe) -> some View {
        Text("PUBLICAR")
            .font(MVFont.bold(15))
            .frame(maxWidth: .infinity).frame(height: 54)
            .foregroundStyle(uni.inkColor)
            .background(uni.color)
            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
            .background(RoundedRectangle(cornerRadius: MV.R.md).fill(MV.C.shadow).offset(x: MV.Shadow.m, y: MV.Shadow.m))
            .contentShape(Rectangle())
            .onTapGesture {
                store.saveLog()
                onPublished()
            }
    }
}
