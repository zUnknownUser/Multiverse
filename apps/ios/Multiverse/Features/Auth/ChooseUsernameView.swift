import SwiftUI

/// Passo 3 de 4: nome de exibição + @usuário (com checagem de disponibilidade).
struct ChooseUsernameView: View {
    @Environment(AuthStore.self) private var auth

    private var suggestions: [String] {
        let base = auth.draft.name.split(separator: " ").first.map { $0.lowercased() } ?? "lorista"
        let seed = Logic.seed(auth.draft.name.isEmpty ? "lorista" : auth.draft.name)
        return ["\(base).azeroth", "\(base)\(100 + Int(seed % 900))"]
    }

    var body: some View {
        @Bindable var auth = auth
        ScreenScaffold(showBack: true, onBack: { auth.pop() }, backTrailing: {
            AnyView(Text(L10n.text("3 DE 4")).font(MVFont.bold(12)).foregroundStyle(MV.C.muted))
        }) {
            VStack(alignment: .leading, spacing: 20) {
                AuthProgressBars(filled: 3)

                Text(L10n.text("COMO TE CHAMAM\nNO MULTIVERSO?"))
                    .font(MVFont.display(30, width: 118))
                    .lineSpacing(-4)
                    .foregroundStyle(MV.C.ink)

                AuthField(label: L10n.text("Nome"), text: $auth.draft.name, placeholder: L10n.text("Seu nome"))

                AuthField(label: L10n.text("Usuário"), text: $auth.draft.username, placeholder: L10n.text("usuario"), autocapitalization: .never) {
                    availabilityBadge
                }
                .task(id: auth.draft.username) {
                    // A single task follows the field's lifetime, including suggestion taps.
                    do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                    await auth.checkUsername()
                }

                if !suggestions.isEmpty {
                    HStack(spacing: 8) {
                        Text(L10n.text("Sugestões:")).font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.ink)
                        ForEach(suggestions, id: \.self) { s in
                            Button {
                                auth.draft.username = s
                            } label: {
                                Text("@\(s)")
                                    .font(MVFont.bold(12))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .foregroundStyle(MV.C.ink)
                                    .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 12)

                PrimaryAuthButton(title: L10n.text("CONTINUAR"), enabled: auth.usernameAvailable == true && !auth.draft.name.isEmpty) {
                    auth.push(.avatarAndBio)
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var availabilityBadge: some View {
        switch auth.usernameAvailable {
        case .some(true):
            badge(L10n.text("✓ DISPONÍVEL"), bg: MV.C.dc, fg: MV.C.card)
        case .some(false):
            badge(L10n.text("INDISPONÍVEL"), bg: MV.C.marvel, fg: MV.C.card)
        case .none:
            EmptyView()
        }
    }

    private func badge(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(MVFont.black(11)).tracking(0.3)
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.sm))
    }
}
