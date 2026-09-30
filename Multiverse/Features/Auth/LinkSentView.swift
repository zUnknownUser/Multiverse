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

            Text("OLHE SEU E-MAIL").font(MVFont.display(34, width: 120)).foregroundStyle(MV.C.ink)

            (Text("Se houver uma conta para ").font(MVFont.body(15, weight: 500))
                + Text(auth.resetEmail).font(MVFont.body(15, weight: 800))
                + Text(" com recuperação disponível, você receberá um link. Confira também o spam.").font(MVFont.body(15, weight: 500)))
                .foregroundStyle(MV.C.ink)

            VStack(spacing: 10) {
                Text("ABRIR APP DE E-MAIL")
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
                                if !accepted { auth.infoMessage = "Abra seu aplicativo de e-mail para acessar o link." }
                            }
                        }
                    }

                Text("VOLTAR PRO LOGIN")
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
                Text("Não chegou?").font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.ink)
                if auth.resendCooldown > 0 {
                    Text("Reenviar em 0:\(String(format: "%02d", auth.resendCooldown))")
                        .font(MVFont.bold(13)).underline().foregroundStyle(MV.C.ink)
                } else {
                    Button("Reenviar") { Task { await auth.requestPasswordReset() } }
                        .font(MVFont.bold(13)).underline().foregroundStyle(MV.C.ink)
                        .buttonStyle(.plain)
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
