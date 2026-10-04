import SwiftUI

/// Passo 4 de 4: avatar da coleção ou iniciais + bio.
struct AvatarAndBioView: View {
    @Environment(AuthStore.self) private var auth
    private let avatarColors = ["#F4A814", "#E4412F", "#2E5BE8", "#16130F"]
    private let bioLimit = 80

    var body: some View {
        @Bindable var auth = auth
        ScreenScaffold(showBack: true, onBack: { auth.pop() }, backTrailing: {
            AnyView(
                Button(L10n.text("PULAR")) { Task { await auth.finishSignUp() } }
                    .font(MVFont.bold(12)).underline().foregroundStyle(MV.C.ink)
                    .buttonStyle(.plain)
            )
        }) {
            VStack(alignment: .leading, spacing: 20) {
                AuthProgressBars(filled: 4)
                Text(L10n.text("SUA CARA NO FEED")).font(MVFont.display(30, width: 120)).foregroundStyle(MV.C.ink)

                VStack(spacing: 8) {
                    ProfileAvatarFace(name: auth.draft.name, color: auth.draft.avatarColor, avatarID: auth.draft.avatarID, size: 140)
                        .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    Text(L10n.text("Escolher avatar")).font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                    ProfileAvatarChoices(selection: $auth.draft.avatarID, name: auth.draft.name, color: auth.draft.avatarColor)
                        .padding(.top, 10)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("OU ESCOLHA A COR DO AVATAR")).kicker(11).foregroundStyle(MV.C.muted)
                    HStack(spacing: 12) {
                        ForEach(avatarColors, id: \.self) { hex in
                            let selected = auth.draft.avatarColor == hex
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 44, height: 44)
                                .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: selected ? 3 : MV.stroke))
                                .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: 1.5).padding(-5).opacity(selected ? 1 : 0))
                                .contentShape(Circle())
                                .onTapGesture { auth.draft.avatarColor = hex; auth.draft.avatarID = nil }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("BIO").kicker(11).foregroundStyle(MV.C.ink)
                        Spacer()
                        Text("\(auth.draft.bio.count)/\(bioLimit)").font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                    }
                    TextField(L10n.text("Conte um pouco sobre você…"), text: $auth.draft.bio, axis: .vertical)
                        .font(MVFont.body(15, weight: 500))
                        .lineLimit(3...4)
                        .padding(12)
                        .background(MV.C.card)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
                        .onChange(of: auth.draft.bio) { _, v in
                            if v.count > bioLimit { auth.draft.bio = String(v.prefix(bioLimit)) }
                        }
                }

                Spacer(minLength: 12)

                VStack(spacing: 8) {
                    PrimaryAuthButton(title: L10n.text("FINALIZAR PERFIL"), isLoading: auth.isLoading) {
                        Task { await auth.finishSignUp() }
                    }
                    Text(L10n.text("Depois disso: escolher universos e seguir loristas."))
                        .font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
    }

}
