import SwiftUI
import PhotosUI

struct PostComposer: View {
    let universe: String?; let item: String?
    var segment = 0; var kind = "discussion"; var club: String? = nil; var schedule: String? = nil; var editing: CommunityPost? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedUniverse = ""
    @State private var title = ""
    @State private var text = ""
    @State private var spoiler = false
    @State private var optionA = ""
    @State private var optionB = ""
    @State private var closesAt = Date.now.addingTimeInterval(86400)
    @State private var busy = false
    @State private var readingPhotos = false
    @State private var error: String?
    @State private var mentioning = false
    @State private var selections: [PhotosPickerItem] = []
    @State private var photos: [ComposerPhoto] = []
    @State private var retained: [PostImage] = []
    @State private var postID = UUID().uuidString.lowercased()
    @State private var pending: (input: PostInput, edit: PostEdit?)?
    @State private var initialized = false
    private var canSend: Bool {
        !busy && !readingPhotos && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.unicodeScalars.count <= 140 && text.unicodeScalars.count <= 5000 && !selectedUniverse.isEmpty && (kind != "duel" || editing != nil || (!optionA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !optionB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && optionA != optionB && optionA.count <= 120 && optionB.count <= 120))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        context
                        editor
                        attachments
                        if kind == "duel" && editing == nil { duelOptions }
                        if pending != nil {
                            Text(L10n.text("Envio pendente. Tente novamente para confirmar sem duplicar sua publicação."))
                                .font(MVFont.body(12)).foregroundStyle(MV.C.muted)
                        }
                        if let error { AuthErrorBanner(message: error) }
                    }.padding(MV.pad).padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) { publishFooter }
            }
            .foregroundStyle(MV.C.ink)
            .background(MV.C.paper)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(MV.C.ink)
        .presentationBackground(MV.C.paper)
        .presentationCornerRadius(MV.R.sheet)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(busy || readingPhotos || pending != nil)
        .sheet(isPresented: $mentioning) { MentionPicker { user in text += (text.isEmpty || text.hasSuffix(" ") ? "" : " ") + user.handle + " " } }
        .onAppear {
            guard !initialized else { return }; initialized = true
            selectedUniverse = editing?.universeID ?? universe ?? store.universes.first?.id ?? ""
            if let editing { postID = editing.id; title = editing.title; text = editing.text; spoiler = editing.spoiler; retained = editing.images ?? [] }
        }
        .task(id: selections) {
            guard !selections.isEmpty else { return }; readingPhotos = true; error = nil
            do {
                var picked: [ComposerPhoto] = []
                for selection in selections {
                    guard let data = try await selection.loadTransferable(type: Data.self) else { throw CommunityError.invalidImage }
                    try Task.checkCancellation(); picked.append(try CommunityPhoto.prepare(data))
                }
                photos += picked.prefix(max(0, 4 - retained.count - photos.count)); selections = []; readingPhotos = false
            } catch is CancellationError { readingPhotos = false } catch { self.error = error.localizedDescription; readingPhotos = false; selections = [] }
        }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("COMUNIDADE")).kicker(10).foregroundStyle(MV.C.muted)
                Text(editing == nil ? L10n.text("NOVA PUBLICAÇÃO") : L10n.text("EDITAR PUBLICAÇÃO"))
                    .font(MVFont.section(22)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                    .frame(width: 44, height: 44).comicCard(radius: MV.R.md, shadow: MV.Shadow.s)
            }
            .buttonStyle(.plain).accessibilityLabel(L10n.text("FECHAR"))
            .disabled(busy || readingPhotos)
        }
        .padding(.horizontal, MV.pad).padding(.top, 24).padding(.bottom, 16)
        .background(MV.C.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(MV.C.divider).frame(height: 1) }
    }

    private var context: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { universeSelector; itemLabel }
                VStack(alignment: .leading, spacing: 8) { universeSelector; itemLabel }
            }
            Label(L10n.text("Publicações da comunidade são públicas, mesmo quando seu diário é privado."), systemImage: "globe")
                .font(MVFont.body(11)).foregroundStyle(MV.C.muted)
                .fixedSize(horizontal: false, vertical: true)
        }.disabled(busy || pending != nil)
    }

    private var universeSelector: some View {
        Group {
            if universe == nil && editing == nil {
                Menu {
                    Picker(L10n.text("Universo"), selection: $selectedUniverse) {
                        ForEach(store.universes) { u in Text(u.name).tag(u.id) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label(store.universe(selectedUniverse)?.name ?? L10n.text("Universo"), systemImage: "sparkles")
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(MVFont.bold(12)).padding(.horizontal, 12).frame(minHeight: 44)
                    .comicCard(radius: MV.R.md, shadow: MV.Shadow.s)
                }.accessibilityLabel(L10n.text("Universo"))
                    .accessibilityValue(store.universe(selectedUniverse)?.name ?? selectedUniverse)
            } else {
                Label(store.universe(selectedUniverse)?.name ?? selectedUniverse, systemImage: "sparkles")
                    .font(MVFont.bold(12)).padding(.horizontal, 12).frame(minHeight: 44)
                    .comicCard(radius: MV.R.md, shadow: MV.Shadow.s)
            }
        }
    }

    @ViewBuilder private var itemLabel: some View {
        if let item {
            Label(store.item(item)?.title ?? item, systemImage: "book.closed")
                .font(MVFont.body(12)).padding(.horizontal, 12).padding(.vertical, 12)
                .background(MV.C.desk, in: RoundedRectangle(cornerRadius: MV.R.md))
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(L10n.text("Título"), text: $title, axis: .vertical)
                .font(MVFont.section(20)).lineLimit(1...4)
                .accessibilityLabel(L10n.text("Título"))
            counter(title.unicodeScalars.count, limit: 140)
            Rectangle().fill(MV.C.divider).frame(height: 1)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(L10n.text("Texto da publicação"))
                        .font(MVFont.body(15)).foregroundStyle(MV.C.muted)
                        .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(MVFont.body(15)).scrollContentBackground(.hidden)
                    .frame(minHeight: 180).accessibilityLabel(L10n.text("Texto da publicação"))
            }
            counter(text.unicodeScalars.count, limit: 5000)
            Rectangle().fill(MV.C.divider).frame(height: 1)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { mentionButton; Spacer(minLength: 0); spoilerToggle }
                VStack(alignment: .leading, spacing: 8) { mentionButton; spoilerToggle }
            }
        }
        .padding(16).comicCard()
        .disabled(busy || pending != nil)
    }

    private func counter(_ count: Int, limit: Int) -> some View {
        Text(verbatim: "\(count)/\(limit)")
            .font(MVFont.body(11)).monospacedDigit()
            .foregroundStyle(count > limit ? MV.C.marvel : MV.C.muted)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var mentionButton: some View {
        Button { mentioning = true } label: {
            Label(L10n.text("MENCIONAR PESSOA"), systemImage: "at")
                .font(MVFont.label(11)).frame(minHeight: 44)
        }.buttonStyle(.plain)
    }

    private var spoilerToggle: some View {
        Toggle(isOn: $spoiler) {
            Label(L10n.text("Contém spoiler"), systemImage: spoiler ? "eye.slash.fill" : "eye")
                .font(MVFont.bold(12))
        }
        .toggleStyle(.button)
        .tint(MV.C.marvel)
        .frame(minHeight: 44)
    }

    private var attachments: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.text("IMAGENS")).kicker()
                Spacer()
                Text(verbatim: "\(retained.count + photos.count)/4").font(MVFont.body(11)).foregroundStyle(MV.C.muted)
                if readingPhotos { ProgressView().controlSize(.small) }
            }
            if retained.isEmpty && photos.isEmpty {
                photoPicker(compact: false)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(retained) { image in
                            CommunityImageView(post: postID, image: image)
                                .frame(width: 104, height: 104).clipped()
                                .comicCard(radius: MV.R.md, shadow: MV.Shadow.s)
                                .overlay(alignment: .topTrailing) {
                                    removePhoto { retained.removeAll { $0.id == image.id } }
                                }
                        }
                        ForEach(photos) { photo in
                            Image(uiImage: photo.preview).resizable().scaledToFill()
                                .frame(width: 104, height: 104).clipped()
                                .comicCard(radius: MV.R.md, shadow: MV.Shadow.s)
                                .overlay(alignment: .topTrailing) {
                                    removePhoto { photos.removeAll { $0.id == photo.id } }
                                }
                        }
                        if retained.count + photos.count < 4 { photoPicker(compact: true) }
                    }.padding(.bottom, 4).padding(.trailing, 4)
                }.scrollIndicators(.hidden)
            }
            Text(L10n.text("Até 4 imagens por publicação."))
                .font(MVFont.body(11)).foregroundStyle(MV.C.muted)
        }.disabled(busy || pending != nil || readingPhotos)
    }

    private func photoPicker(compact: Bool) -> some View {
        PhotosPicker(selection: $selections, maxSelectionCount: max(1, 4 - retained.count - photos.count), matching: .images, preferredItemEncoding: .compatible) {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus").font(.system(size: compact ? 22 : 26, weight: .medium))
                Text(L10n.text("ADICIONAR IMAGENS"))
                    .font(MVFont.label(10)).multilineTextAlignment(.center)
            }
            .padding(12)
            .frame(width: compact ? 104 : nil, height: compact ? 104 : nil)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? nil : 100)
        }
        .buttonStyle(.plain)
        .comicCard(bg: MV.C.paper, radius: MV.R.md, shadow: 0, dashed: true)
    }

    private func removePhoto(action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                .foregroundStyle(MV.C.ink).frame(width: 26, height: 26)
                .background(MV.C.card, in: Circle())
                .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .frame(width: 44, height: 44)
        }.buttonStyle(.plain).accessibilityLabel(L10n.text("REMOVER"))
    }

    private var duelOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(L10n.text("Opção A"), text: $optionA).font(MVFont.bold(14))
            Rectangle().fill(MV.C.divider).frame(height: 1)
            TextField(L10n.text("Opção B"), text: $optionB).font(MVFont.bold(14))
            Rectangle().fill(MV.C.divider).frame(height: 1)
            DatePicker(L10n.text("Encerrar votação"), selection: $closesAt, in: Date.now...Date.now.addingTimeInterval(29 * 86400))
                .font(MVFont.body(12))
        }.padding(16).comicCard().disabled(busy || pending != nil)
    }

    private var publishFooter: some View {
        Button { Task { await publish() } } label: {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(MV.C.muted) }
                Text(busy ? L10n.text("ENVIANDO…") : editing == nil ? L10n.text("PUBLICAR") : L10n.text("SALVAR ALTERAÇÕES"))
                    .font(MVFont.label(14))
                if !busy { Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .bold)) }
            }
            .foregroundStyle(canSend ? Color(hex: "#16130F") : MV.C.muted)
            .padding(.horizontal, 16).padding(.vertical, 16).frame(maxWidth: .infinity, minHeight: 52)
            .comicCard(bg: canSend ? MV.C.accent : MV.C.desk, radius: MV.R.md, shadow: MV.Shadow.s)
        }
        .buttonStyle(.plain).disabled(!canSend)
        .padding(.horizontal, MV.pad).padding(.top, 12).padding(.bottom, 12)
        .background(MV.C.paper)
        .overlay(alignment: .top) { Rectangle().fill(MV.C.divider).frame(height: 1) }
    }

    private func publish() async {
        guard let api = store.communityAPI else { return }; busy = true; error = nil
        defer { busy = false }
        if pending == nil {
            let ids = retained.map(\.id) + photos.map(\.id)
            var input = PostInput(universeID: selectedUniverse, itemID: item, title: title, text: text, spoiler: spoiler)
            input.imageIDs = ids; input.segment = segment; input.kind = kind; input.clubID = club; input.scheduleID = schedule
            if kind == "duel" { input.optionA = optionA; input.optionB = optionB; input.closesAt = ISO8601DateFormatter().string(from: closesAt) }
            let edit = editing.map { PostEdit(title: title, text: text, spoiler: spoiler, imageIDs: ids, version: $0.version ?? 1, mutationID: UUID().uuidString.lowercased()) }
            pending = (input, edit)
        }
        guard let pending else { return }
        do {
            for photo in photos {
                let uploaded = try await api.uploadPostImage(post: postID, id: photo.id, data: photo.data)
                guard uploaded.id == photo.id else { throw SocialError.invalid }
            }
            let receipt: PostReceipt
            if let edit = pending.edit { receipt = try await api.editPost(postID, input: edit) }
            else { receipt = try await api.publishPost(id: postID, input: pending.input) }
            guard receipt.saved, receipt.id == postID else { throw SocialError.invalid }
            self.pending = nil; dismiss()
            if editing == nil { store.push(.post(receipt.id)) }
        } catch { self.error = error.localizedDescription }
    }
}
