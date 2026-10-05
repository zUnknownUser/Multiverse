import SwiftUI
import PhotosUI

struct ProfileEditorView: View {
    let user: User
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var bio: String
    @State private var avatarID: String?
    @State private var color: String
    @State private var picker: PhotosPickerItem?
    @State private var photo: PreparedPhoto?
    @State private var photoAction = "keep"
    @State private var preparing = false
    @State private var saving = false
    @State private var error: String?
    init(user: User) {
        self.user = user
        _name = State(initialValue: user.name)
        _bio = State(initialValue: user.bio)
        _avatarID = State(initialValue: user.avatarID)
        _color = State(initialValue: user.avatarColor)
    }
    private var hasPhoto: Bool { photo != nil || (photoAction == "keep" && user.avatarPhotoID != nil) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 14) {
                        ProfileAvatarFace(name: name, color: color, avatarID: avatarID, size: 120)
                            .overlay {
                                if let photo { Image(uiImage: photo.preview).resizable().scaledToFill() }
                                else if photoAction == "keep" { AvatarPhotoOverlay(id: user.avatarPhotoID) }
                            }
                            .frame(width: 120, height: 120).clipShape(Circle())
                            .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        PhotosPicker(selection: $picker, matching: .images, preferredItemEncoding: .compatible) {
                            Label(L10n.text(hasPhoto ? "Trocar foto" : "Escolher foto"), systemImage: "photo")
                                .font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                        }.disabled(preparing || saving)
                        if preparing { ProgressView() }
                        if hasPhoto {
                            Button(L10n.text("Remover foto")) { photo = nil; picker = nil; photoAction = "remove" }
                                .font(MVFont.body(12)).foregroundStyle(MV.C.marvel)
                        }
                    }.frame(maxWidth: .infinity)
                    ProfileAvatarChoices(selection: $avatarID, name: name, color: color, showSelection: !hasPhoto) {
                        photo = nil; picker = nil; photoAction = "remove"
                    }
                    if !hasPhoto && avatarID == nil {
                        HStack(spacing: 14) {
                            ForEach(["#F4A814", "#E4412F", "#2E5BE8", "#16130F"], id: \.self) { hex in
                                Button { color = hex } label: {
                                    Circle().fill(Color(hex: hex)).frame(width: 36, height: 36)
                                        .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: color == hex ? 3 : 1))
                                }.accessibilityLabel(hex).accessibilityAddTraits(color == hex ? .isSelected : [])
                            }
                        }.frame(maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("NOME")).kicker().foregroundStyle(MV.C.muted)
                        TextField(L10n.text("Seu nome"), text: $name).textContentType(.name)
                            .padding(12).background(MV.C.card).comicCard(bg: MV.C.card, shadow: 0)
                            .onChange(of: name) { _, value in if value.count > 80 { name = String(value.prefix(80)) } }
                        Text(user.handle).font(MVFont.body(12)).foregroundStyle(MV.C.muted)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("BIO").kicker(); Spacer(); Text(verbatim: "\(bio.count)/160").font(MVFont.body(11)) }.foregroundStyle(MV.C.muted)
                        TextField(L10n.text("Conte um pouco sobre você…"), text: $bio, axis: .vertical)
                            .lineLimit(3...5).padding(12).background(MV.C.card).comicCard(bg: MV.C.card, shadow: 0)
                            .onChange(of: bio) { _, value in if value.count > 160 { bio = String(value.prefix(160)) } }
                    }
                    if let error { AuthErrorBanner(message: error) }
                    PrimaryAuthButton(title: L10n.text("SALVAR PERFIL"), isLoading: saving) {
                        guard !saving && !preparing else { return }
                        saving = true; error = nil
                        let input = ProfileEditInput(displayName: name.trimmingCharacters(in: .whitespacesAndNewlines), bio: bio, avatarColor: color, avatarID: avatarID, photoAction: photoAction, photo: photo?.data.base64EncodedString())
                        Task {
                            do { try await store.editProfile(input); dismiss() }
                            catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }.disabled(preparing || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.font(MVFont.body(15)).foregroundStyle(MV.C.ink).padding(24).disabled(saving)
            }.scrollDismissesKeyboard(.interactively).background(MV.C.paper)
                .navigationTitle(L10n.text("Editar perfil")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancelar")) { dismiss() }.disabled(saving) } }
        }.presentationDetents([.large]).interactiveDismissDisabled(saving)
            .task(id: picker) {
                guard let picker else { return }
                preparing = true; error = nil
                defer { preparing = false }
                do {
                    guard let data = try await picker.loadTransferable(type: Data.self) else { throw CommunityError.invalidImage }
                    let prepared = try await PhotoProcessor.shared.prepare(data)
                    try Task.checkCancellation()
                    photo = prepared; photoAction = "replace"
                } catch is CancellationError {} catch { self.error = error.localizedDescription }
            }
    }
}
