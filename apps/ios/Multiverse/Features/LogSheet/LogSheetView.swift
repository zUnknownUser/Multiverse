import SwiftUI

/// Bottom sheet de registro — aberto pelo botão + da tab bar ou por "Registrar"/"Avaliar"
/// numa Obra. `AppStore.logDraft` guia se mostramos a grade de escolha ou o formulário.
struct LogSheetView: View {
    @Environment(AppStore.self) private var store

    @State private var confirmingDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(MV.C.ink).frame(width: 44, height: 5).padding(.top, 10).padding(.bottom, 14)

            HStack {
                Button(L10n.text("FECHAR")) { store.closeLog() }
                Spacer()
                Button(L10n.text("DESCARTAR RASCUNHO"), role: .destructive) { confirmingDiscard = true }
            }.font(MVFont.bold(11)).padding(.horizontal, MV.pad).padding(.bottom, 12).disabled(store.isSavingLog)
            if let error = store.draftStorageError { AuthErrorBanner(message: error).padding(.horizontal, MV.pad) }
            ScrollView {
                if store.logDraft?.itemID == nil {
                    PickItemContent()
                } else if let id = store.logDraft?.itemID {
                    CatalogReferenceStatus(ids: [id]).padding(MV.pad)
                    if store.item(id) != nil { LogFormContent() }
                    else if store.catalogStore.missingIDs.contains(id) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.text("Obra indisponível no catálogo"))
                            Text(store.logDraft?.text ?? "").textSelection(.enabled)
                        }.padding(MV.pad)
                    }
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
        .interactiveDismissDisabled(store.isSavingLog)
        .confirmationDialog(L10n.text("Descartar este rascunho?"), isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button(L10n.text("DESCARTAR RASCUNHO"), role: .destructive) { store.discardLogDraft() }
            Button(L10n.text("Cancelar"), role: .cancel) {}
        }
        .task { await store.social?.loadPrivacy() }
        .task(id: store.logDraft?.itemID) { if let id = store.logDraft?.itemID { await store.catalogStore.resolve([id]) } }
    }
}

private struct PickItemContent: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    private var catalogQuery: CatalogQuery { .init(text: query, category: "consumable") }
    private var matchingItems: [Item] { store.catalogStore.paginated ? store.catalogStore.page(catalogQuery).values : store.logPickerItems.filter { ProductSearch.matches($0.title, query: query) } }
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("O QUE VOCÊ VIU, LEU OU JOGOU?"))
                .font(MVFont.section(18)).foregroundStyle(MV.C.ink)
            TextField(L10n.text("Buscar obra pelo título"), text: $query)
                .padding(12).comicCard(shadow: MV.Shadow.s).autocorrectionDisabled()
            if matchingItems.isEmpty && (!store.catalogStore.paginated || store.catalogStore.page(catalogQuery).loaded) && !store.logPickerItems.isEmpty {
                Text(L10n.text("Nenhuma obra encontrada. Tente outro título.")).font(MVFont.body(14)).foregroundStyle(MV.C.muted)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(matchingItems) { item in
                        Button { store.setLogItem(item.id) } label: {
                            PosterView(item: item, universe: store.universe(of: item), width: 104, height: 156, titleSize: 11)
                        }
                        .buttonStyle(.plain)
                }
            }
            if store.catalogStore.paginated {
                CatalogPageControls(state: store.catalogStore.page(catalogQuery)) { more in await store.catalogStore.load(catalogQuery, more: more) }
            }
            if !store.catalogStore.paginated && store.logPickerItems.isEmpty {
                Text(L10n.text("Ainda não há itens disponíveis para registrar. Volte em instantes."))
                    .font(MVFont.body(14)).foregroundStyle(MV.C.muted)
            }
        }
        .padding(.horizontal, MV.pad)
        .padding(.bottom, 24)
        .task(id: CatalogTaskKey(query: catalogQuery, generation: store.catalogStore.generation)) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await store.catalogStore.load(catalogQuery)
        }
    }
}

private struct LogFormContent: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let itemID = store.logDraft?.itemID, let item = store.item(itemID) {
            let uni = store.universe(of: item)
            let rating = store.logDraft?.rating ?? 0

            VStack(alignment: .leading, spacing: 18) {
                if store.logDraft?.isEditing == true {
                    HStack {
                        Text(L10n.text("EDITAR REGISTRO")).font(MVFont.section(18)).foregroundStyle(MV.C.ink)
                        Spacer()
                        Button(L10n.text("FECHAR")) { store.closeLog() }
                            .font(MVFont.bold(12)).foregroundStyle(MV.C.muted)
                    }
                }
                header(item: item, uni: uni)
                if store.logDraft?.isEditing == true {
                    DatePicker(L10n.text("Data do registro"), selection: Binding(
                        get: { store.logDraft?.loggedAt ?? .now },
                        set: { store.logDraft?.loggedAt = $0 }
                    ), in: ...Date.now, displayedComponents: .date)
                        .font(MVFont.body(13, weight: 600)).tint(uni.color)
                }
                ratingPicker(uni: uni, rating: rating)
                togglePills
                reviewField
                Text(L10n.text(store.social == nil ? "Sua nota e review serão salvas com este registro." :
                    store.social?.publicDiary == true ? "Diário público: esta review poderá aparecer para quem segue você." :
                    store.social?.publicDiary == false ? "Diário privado: esta review fica só para você. Altere em Ajustes quando quiser." :
                    "Confira a visibilidade do diário em Ajustes."))
                    .font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                if let error = store.logSaveError { AuthErrorBanner(message: error) }
                publishButton(item: item, uni: uni)
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
            .disabled(store.isSavingLog)
            .allowsHitTesting(!store.isSavingLog)
        } else {
            Text(L10n.text("A obra deste rascunho não está disponível. Atualize o catálogo ou descarte o rascunho para começar outro."))
                .font(MVFont.body(14)).foregroundStyle(MV.C.muted).padding(MV.pad)
        }
    }

    @ViewBuilder
    private func header(item: Item, uni: Universe) -> some View {
        HStack(spacing: 12) {
            PosterView(item: item, universe: uni, width: 52, height: 78, titleSize: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.logDraft?.isEditing == true
                     ? L10n.date(store.logDraft?.loggedAt ?? .now, template: "d MMM yyyy")
                     : L10n.format("%1$@ · Hoje, %2$@", String(describing: Logic.verb(item.type)), L10n.date(.now, template: "d MMM")))
                    .font(MVFont.body(11, weight: 700)).foregroundStyle(MV.C.muted)
                Text(item.title).font(MVFont.bold(17)).foregroundStyle(MV.C.ink)
                Text("\(uni.name) · \(L10n.text(item.type))").font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func ratingPicker(uni: Universe, rating: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("NOTA")).kicker(11).foregroundStyle(MV.C.muted)
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
            Text(rating > 0 ? Logic.starHint(rating) : L10n.text("Toque de novo pra meia estrela"))
                .font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.muted)
        }
    }

    private var togglePills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { toggles }
            VStack(alignment: .leading, spacing: 8) { toggles }
        }
    }

    @ViewBuilder private var toggles: some View {
        pill(L10n.text("♥ Curti"), isOn: store.logDraft?.liked ?? false) { toggle(\.liked) }
        pill(L10n.text("↻ Revisitei"), isOn: store.logDraft?.rewatch ?? false) { toggle(\.rewatch) }
        pill(L10n.text("⚠ Contém spoiler"), isOn: store.logDraft?.spoiler ?? false) { toggle(\.spoiler) }
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
            Text(L10n.text("SUA REVIEW")).kicker(11).foregroundStyle(MV.C.muted)
            TextField(
                L10n.text("Escreva sua review… teorias de cânone são bem-vindas."),
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
        Button { store.saveLog() } label: {
            Text(store.isSavingLog ? L10n.text("SALVANDO…") : store.logDraft?.isEditing == true ? L10n.text("SALVAR ALTERAÇÕES") : L10n.text("PUBLICAR"))
                .font(MVFont.bold(15))
                .frame(maxWidth: .infinity).frame(height: 54)
                .foregroundStyle(uni.inkColor)
                .background(uni.color)
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                .background(RoundedRectangle(cornerRadius: MV.R.md).fill(MV.C.shadow).offset(x: MV.Shadow.m, y: MV.Shadow.m))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
