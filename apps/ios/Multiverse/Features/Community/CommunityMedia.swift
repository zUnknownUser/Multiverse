import SwiftUI
import PhotosUI
import ImageIO

struct CommunityImageView: View {
    let post: String; let image: PostImage
    @Environment(AppStore.self) private var store
    @State private var picture: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let picture { Image(uiImage: picture).resizable().scaledToFit().accessibilityLabel(L10n.text("Imagem da publicação")) }
            else if failed { Button(L10n.text("RECARREGAR IMAGEM")) { Task { await load() } }.frame(minHeight: 80) }
            else { ProgressView().frame(maxWidth: .infinity, minHeight: 80) }
        }.clipShape(RoundedRectangle(cornerRadius: MV.R.md)).task(id: image.id) { await load() }
    }
    private func load() async {
        guard picture == nil, let api = store.communityAPI else { return }; failed = false
        do {
            let response = try await api.fetchPostImage(post: post, id: image.id)
            try Task.checkCancellation()
            guard response.id == image.id, let data = Data(base64Encoded: response.base64), data.count <= 1_048_576, let decoded = UIImage(data: data) else { throw SocialError.invalid }
            picture = decoded
        } catch is CancellationError { } catch { failed = true }
    }
}
struct MentionedText: View {
    let text: String; let mentions: [PostMention]
    @Environment(AppStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).textSelection(.enabled)
            if !mentions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(mentions) { person in Button(person.handle) { store.openUserProfile(person.id) }.font(MVFont.bold(12)) } }
                }
            }
        }
    }
}
struct MentionPicker: View {
    let selected: (User) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var users: [User] = []
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            List {
                if busy { ProgressView() }
                if let error { AuthErrorBanner(message: error) }
                ForEach(users) { user in
                    Button { selected(user); dismiss() } label: {
                        HStack { AvatarView(user: user, size: 32); VStack(alignment: .leading) { Text(user.name); Text(user.handle).font(.caption) } }
                    }
                }
                if !busy && users.isEmpty && !query.isEmpty && error == nil { Text(L10n.text("Nenhuma pessoa encontrada.")) }
            }.searchable(text: $query, prompt: L10n.text("Buscar nome ou @usuário"))
            .navigationTitle(L10n.text("MENCIONAR PESSOA"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("FECHAR")) { dismiss() } } }
            .task(id: query) {
                let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
                users = []; error = nil; busy = false
                guard !value.isEmpty, value.count <= 80, let api = store.communityAPI else { return }
                do {
                    try await Task.sleep(for: .milliseconds(300)); busy = true
                    let result = try await api.mentionPeople(query: value)
                    try Task.checkCancellation(); users = result; busy = false
                } catch is CancellationError { } catch { self.error = error.localizedDescription; busy = false }
            }
        }
    }
}
struct ComposerPhoto: Identifiable { let id: String; let data: Data; let preview: UIImage }
enum CommunityPhoto {
    static func prepare(_ data: Data) throws -> ComposerPhoto {
        guard data.count <= 30_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw CommunityError.invalidImage }
        let picture = UIImage(cgImage: thumbnail)
        guard let jpeg = picture.jpegData(compressionQuality: 0.8), jpeg.count <= 2_000_000 else { throw CommunityError.invalidImage }
        return ComposerPhoto(id: UUID().uuidString.lowercased(), data: jpeg, preview: picture)
    }
}
