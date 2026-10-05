import SwiftUI

struct ProfileAvatarChoices: View {
    @Binding var selection: String?
    let name: String
    let color: String
    var showSelection = true
    var onChoose: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 12) {
            choice(nil, title: L10n.text("Iniciais"))
            ForEach(ProfileAvatar.allCases) { avatar in choice(avatar.rawValue, title: avatar.title) }
        }.frame(maxWidth: .infinity)
    }
    private func choice(_ id: String?, title: String) -> some View {
        Button { selection = id; onChoose?() } label: {
            ProfileAvatarFace(name: name, color: color, avatarID: id, size: 52)
                .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .overlay(Circle().strokeBorder(MV.C.accent, lineWidth: 3).padding(-4).opacity(showSelection && selection == id ? 1 : 0))
        }
        .buttonStyle(.plain).accessibilityLabel(title)
        .accessibilityAddTraits(showSelection && selection == id ? .isSelected : [])
    }
}
