import SwiftUI

/// Container padrão de tela: fundo papel, scroll, botão "← VOLTAR" opcional no topo
/// (a navigation bar nativa fica escondida em todas as telas).
struct ScreenScaffold<Content: View>: View {
    var showBack = false
    var onBack: (() -> Void)? = nil
    var backTrailing: (() -> AnyView)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if showBack {
                        BackButtonBar(action: { onBack?() }, trailing: backTrailing)
                    } else {
                        Color.clear.frame(height: 12)
                    }
                    content()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            BurstOverlay()
        }
        .background(MV.C.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .coordinateSpace(name: "screen")
    }
}

/// Título de seção: 900, 115%, 18–20pt, UPPERCASE, com link opcional à direita ("VER TUDO").
struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var onTrailing: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(MVFont.section(19))
                .textCase(.uppercase)
                .foregroundStyle(MV.C.ink)
            Spacer()
            if let trailing {
                Button(action: { onTrailing?() }) {
                    Text(trailing)
                        .kicker(11)
                        .underline()
                        .foregroundStyle(MV.C.ink)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
