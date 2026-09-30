import SwiftUI

struct BlockedUsersView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var blocked: [BlockedUser] = []

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BLOQUEADOS").font(MVFont.display(30, width: 122)).foregroundStyle(MV.C.ink)
                    Text("Quem está aqui não vê seu perfil, não comenta nas suas reviews e some do seu feed.")
                        .font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)
                }

                VStack(spacing: 10) {
                    ForEach(blocked) { user in
                        BlockedUserRow(user: user) {
                            Task {
                                await auth.unblock(user.id)
                                blocked.removeAll { $0.id == user.id }
                            }
                        }
                    }
                }

                Text("Pra bloquear alguém, abra o perfil da pessoa e toque em ••• → Bloquear. Ela não é avisada.")
                    .font(MVFont.body(13, weight: 500))
                    .foregroundStyle(MV.C.ink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .comicCard(shadow: 0, dashed: true)
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
        .task { blocked = await auth.loadBlockedUsers() }
    }
}

private struct BlockedUserRow: View {
    let user: BlockedUser
    let onUnblock: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                MV.C.ink
                Text(Logic.initials(user.handle.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "@", with: "")))
                    .font(MVFont.black(13)).foregroundStyle(MV.C.paper)
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))

            VStack(alignment: .leading, spacing: 2) {
                Text(user.handle).font(MVFont.bold(15)).foregroundStyle(MV.C.ink)
                Text("Bloqueado em \(user.blockedOn)").font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
            }
            Spacer()

            Text("DESBLOQUEAR")
                .font(MVFont.bold(11))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .foregroundStyle(MV.C.ink)
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .contentShape(Rectangle())
                .onTapGesture(perform: onUnblock)
        }
        .padding(12)
        .comicCard(shadow: MV.Shadow.s)
    }
}
