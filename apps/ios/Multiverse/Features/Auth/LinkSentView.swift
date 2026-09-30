import SwiftUI

struct LinkSentView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()

            Text("ZAP!")
                .font(MVFont.display(26))
                .foregroundStyle(MV.C.card)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(MV.C.dc)
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .background(RoundedRectangle(cornerRadius: MV.R.md).fill(MV.C.shadow).offset(x: MV.Shadow.m, y: MV.Shadow.m))
                .rotationEffect(.degrees(-3))

            Text(L10n.text("OLHE SEU E-MAIL")).font(MVFont.display(34, width: 120)).foregroundStyle(MV.C.ink)

            (Text(L10n.text("Se houver uma conta para ")).font(MVFont.body(15, weight: 500))
                + Text(auth.resetEmail).font(MVFont.body(15, weight: 800))
                + Text(L10n.text(" com recuperação disponível, você receberá um link. Confira também o spam.")).font(MVFont.body(15, weight: 500)))
                .foregroundStyle(MV.C.ink)

            VStack(spacing: 10) {
                Text(L10n.text("ABRIR APP DE E-MAIL"))
                    .font(MVFont.bold(14))
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .foregroundStyle(MV.C.paper)
                    .background(MV.C.ink)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .background(RoundedRectangle(cornerRadius: MV.R.md).fill(MV.C.marvel).offset(x: MV.Shadow.s, y: MV.Shadow.s))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let url = URL(string: "message://") {
                            openURL(url) { accepted in
                                if !accepted { auth.infoMessage = L10n.text("Abra seu aplicativo de e-mail para acessar o link.") }
                            }
                        }
                    }

                Text(L10n.text("VOLTAR PRO LOGIN"))
                    .font(MVFont.bold(14))
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .foregroundStyle(MV.C.ink)
                    .background(MV.C.card)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        auth.returnToLogin()
                    }
            }
            .padding(.top, 8)

            Spacer()

            HStack {
                Spacer()
                Text(L10n.text("Não chegou?")).font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.ink)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let remaining = auth.passwordResetResendCooldown
                    if remaining > 0 {
                        Text(L10n.format("Reenviar em %1$@", String(format: "%d:%02d", remaining / 60, remaining % 60)))
                            .font(MVFont.bold(13)).underline().foregroundStyle(MV.C.ink)
                    } else {
                        Button(L10n.text("Reenviar")) { Task { await auth.requestPasswordReset() } }
                            .font(MVFont.bold(13)).underline().foregroundStyle(MV.C.ink)
                            .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, MV.pad)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MV.C.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
