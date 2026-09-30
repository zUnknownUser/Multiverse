import SwiftUI

/// Aplica em qualquer view pra disparar uma onomatopeia (`BurstOverlay`) no ponto do toque.
/// Todas as telas que usam isso precisam estar dentro de `.coordinateSpace(name: "screen")`.
private struct BurstTapModifier: ViewModifier {
    let text: String
    let color: Color
    let textColor: Color
    let condition: Bool
    let action: () -> Void
    @Environment(BurstCenter.self) private var burst
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { frame = geo.frame(in: .named("screen")) }
                        .onChange(of: geo.size) { _, _ in frame = geo.frame(in: .named("screen")) }
                }
            )
            .onTapGesture {
                if condition {
                    burst.fire(text, color, textColor: textColor, at: CGPoint(x: frame.midX, y: frame.midY))
                }
                action()
            }
    }
}

extension View {
    /// Dispara `text` (POW!, BAM!, ZAP!, KRAK!, BOOM!, SHARE!) na cor `color` ao tocar,
    /// só quando `condition` é verdadeiro (ex.: ainda não votou), e sempre chama `perform`.
    func burstOnTap(_ text: String, color: Color, textColor: Color = MV.C.paper, when condition: Bool = true, perform: @escaping () -> Void) -> some View {
        modifier(BurstTapModifier(text: text, color: color, textColor: textColor, condition: condition, action: perform))
    }
}
