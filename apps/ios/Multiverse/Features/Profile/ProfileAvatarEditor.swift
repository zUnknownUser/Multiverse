import SwiftUI

struct ProfileAvatarChoices: View {
    @Binding var selection: String?
    let name: String
    let color: String
    var body: some View {
        HStack(spacing: 12) {
            choice(nil, title: L10n.text("Iniciais"))
            ForEach(ProfileAvatar.allCases) { avatar in choice(avatar.rawValue, title: avatar.title) }
        }.frame(maxWidth: .infinity)
    }
    private func choice(_ id: String?, title: String) -> some View {
        Button { selection = id } label: {
            ProfileAvatarFace(name: name, color: color, avatarID: id, size: 52)
                .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .overlay(Circle().strokeBorder(MV.C.accent, lineWidth: 3).padding(-4).opacity(selection == id ? 1 : 0))
        }
        .buttonStyle(.plain).accessibilityLabel(title)
        .accessibilityAddTraits(selection == id ? .isSelected : [])
    }
}

struct ProfileAvatarEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var selection: String?
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let user = store.user(store.meID) {
                    ProfileAvatarFace(name: user.name, color: user.avatarColor, avatarID: selection, size: 140)
                        .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    ProfileAvatarChoices(selection: $selection, name: user.name, color: user.avatarColor)
                    if let error { AuthErrorBanner(message: error) }
                    PrimaryAuthButton(title: L10n.text("SALVAR AVATAR"), isLoading: saving) {
                        guard !saving else { return }
                        saving = true; error = nil
                        Task {
                            do { try await store.saveAvatar(selection); dismiss() }
                            catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(24).background(MV.C.paper)
            .navigationTitle(L10n.text("Escolher avatar")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancelar")) { dismiss() }.disabled(saving) } }
            .disabled(saving)
        }
        .presentationDetents([.medium, .large]).interactiveDismissDisabled(saving)
    }
}
