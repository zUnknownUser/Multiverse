import SwiftUI

struct WelcomeView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(BurstCenter.self) private var burst

    var body: some View {
        ZStack {
            MV.C.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                collage.frame(height: 340)
                content
            }
            BurstOverlay()
        }
        .coordinateSpace(name: "screen")
        .toolbar(.hidden, for: .navigationBar)
    }

    private var collage: some View {
        GeometryReader { geo in
            ZStack {
                tile(MV.C.dc, x: 0.06, y: 0.28, w: 0.24, h: 0.46, rot: -8)
                tile(MV.C.ink, x: 0.32, y: 0.38, w: 0.26, h: 0.5, rot: -4)
                tile(MV.C.wow, x: 0.62, y: 0.22, w: 0.26, h: 0.48, rot: 7)
                tile(MV.C.dc, x: 0.06, y: 0.78, w: 0.22, h: 0.42, rot: -6)
                tile(MV.C.wow, x: 0.3, y: 0.86, w: 0.24, h: 0.4, rot: 5)
                tile(MV.C.marvel, x: 0.58, y: 0.82, w: 0.26, h: 0.44, rot: -3)
                tile(MV.C.ink, x: 0.86, y: 0.66, w: 0.22, h: 0.42, rot: 8)

                Text("MARVEL · DC · WARCRAFT")
                    .font(MVFont.black(15)).tracking(0.5)
                    .foregroundStyle(MV.C.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(MV.C.wow)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .background(RoundedRectangle(cornerRadius: MV.R.sm).fill(MV.C.ink).offset(x: 3, y: 3))
                    .rotationEffect(.degrees(-6))
                    .position(x: geo.size.width * 0.58, y: geo.size.height * 0.16)

                Text("POW!")
                    .font(MVFont.display(16))
                    .foregroundStyle(MV.C.ink)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(MV.C.card)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .background(RoundedRectangle(cornerRadius: MV.R.sm).fill(MV.C.ink).offset(x: 3, y: 3))
                    .rotationEffect(.degrees(-8))
                    .position(x: geo.size.width * 0.14, y: geo.size.height * 0.9)
            }
        }
        .clipped()
    }

    private func tile(_ color: Color, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, rot: Double) -> some View {
        GeometryReader { geo in
            ZStack { color; Halftone(color: MV.C.ink.opacity(0.18)) }
                .frame(width: geo.size.width * w, height: geo.size.height * h)
                .overlay(RoundedRectangle(cornerRadius: MV.R.poster).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.poster))
                .rotationEffect(.degrees(rot))
                .position(x: geo.size.width * x + geo.size.width * w / 2, y: geo.size.height * y)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("MULTIVERSE")
                .font(MVFont.display(44, width: 125))
                .tracking(-0.5)
                .foregroundStyle(MV.C.ink)

            Text("Registre, avalie e discuta todo o cânone dos seus universos favoritos.")
                .font(MVFont.body(15, weight: 500))
                .foregroundStyle(MV.C.ink)

            VStack(spacing: 12) {
                socialButton("Continuar com Apple", bg: MV.C.ink, fg: MV.C.paper, shadowColor: MV.C.marvel) {
                    Task { await auth.continueWithApple() }
                }
                socialButton("Continuar com Google", bg: MV.C.card, fg: MV.C.ink, shadowColor: MV.C.ink) {
                    Task { await auth.continueWithGoogle() }
                }
                socialButton("Criar conta com e-mail", bg: MV.C.card, fg: MV.C.ink, shadowColor: MV.C.ink) {
                    auth.push(.createAccount)
                }
            }
            .padding(.top, 4)

            HStack {
                Spacer()
                Button { auth.push(.signIn) } label: {
                    (Text("Já tem conta? ").foregroundStyle(MV.C.ink)
                        + Text("Entrar").underline().foregroundStyle(MV.C.ink).bold())
                        .font(MVFont.body(15, weight: 600))
                }
                .buttonStyle(.plain)
                Spacer()
            }

            Spacer(minLength: 8)

            Text("Ao continuar, você aceita os **Termos de Uso** e a **Política de Privacidade**.")
                .font(MVFont.body(11, weight: 500))
                .foregroundStyle(MV.C.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, MV.pad)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private func socialButton(_ title: String, bg: Color, fg: Color, shadowColor: Color, action: @escaping () -> Void) -> some View {
        Text(title)
            .font(MVFont.bold(15))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(fg)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
            .background(RoundedRectangle(cornerRadius: MV.R.md).fill(shadowColor).offset(x: MV.Shadow.s, y: MV.Shadow.s))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}
