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
            Form {
                Section {
                    Text(L10n.text("Publicações da comunidade são públicas, mesmo quando seu diário é privado."))
                    if universe == nil && editing == nil {
                        Picker(L10n.text("Universo"), selection: $selectedUniverse) { ForEach(store.universes) { u in Text(u.name).tag(u.id) } }
                    } else { Text(store.universe(selectedUniverse)?.name ?? selectedUniverse) }
                    if let item { Text(store.item(item)?.title ?? item) }
                    TextField(L10n.text("Título"), text: $title, axis: .vertical)
                    TextEditor(text: $text).frame(minHeight: 160).accessibilityLabel(L10n.text("Texto da publicação"))
                    Text("\(title.unicodeScalars.count)/140 · \(text.unicodeScalars.count)/5000").font(.caption)
                    Button(L10n.text("MENCIONAR PESSOA")) { mentioning = true }
                    Toggle(L10n.text("Contém spoiler"), isOn: $spoiler)
                    if kind == "duel" && editing == nil {
                        TextField(L10n.text("Opção A"), text: $optionA)
                        TextField(L10n.text("Opção B"), text: $optionB)
                        DatePicker(L10n.text("Encerrar votação"), selection: $closesAt, in: Date.now...Date.now.addingTimeInterval(29 * 86400))
                    }
                }.disabled(busy || pending != nil)
                Section(L10n.text("IMAGENS")) {
                    ForEach(retained) { image in
                        HStack { CommunityImageView(post: postID, image: image).frame(height: 90); Spacer(); Button(L10n.text("REMOVER"), role: .destructive) { retained.removeAll { $0.id == image.id } } }
                    }
                    ForEach(photos) { photo in
                        HStack { Image(uiImage: photo.preview).resizable().scaledToFit().frame(height: 90); Spacer(); Button(L10n.text("REMOVER"), role: .destructive) { photos.removeAll { $0.id == photo.id } } }
                    }
                    if retained.count + photos.count < 4 {
                        PhotosPicker(selection: $selections, maxSelectionCount: 4 - retained.count - photos.count, matching: .images, preferredItemEncoding: .compatible) { Label(L10n.text("ADICIONAR IMAGENS"), systemImage: "photo.on.rectangle.angled") }
                    }
                    if readingPhotos { ProgressView() }
                    Text(L10n.text("Até 4 imagens por publicação.")).font(.caption)
                }.disabled(busy || pending != nil || readingPhotos)
                if pending != nil { Text(L10n.text("Envio pendente. Tente novamente para confirmar sem duplicar sua publicação.")) }
                if let error { AuthErrorBanner(message: error) }
                Button(busy ? L10n.text("ENVIANDO…") : editing == nil ? L10n.text("PUBLICAR") : L10n.text("SALVAR ALTERAÇÕES")) { Task { await publish() } }.disabled(!canSend)
            }.navigationTitle(editing == nil ? L10n.text("NOVA PUBLICAÇÃO") : L10n.text("EDITAR PUBLICAÇÃO"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("FECHAR")) { dismiss() }.disabled(busy) } }
        }.interactiveDismissDisabled(busy || readingPhotos || pending != nil)
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
