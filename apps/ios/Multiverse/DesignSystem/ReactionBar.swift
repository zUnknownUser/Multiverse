import SwiftUI

/// Barra de reações que aparece ao segurar um card de review (recurso 5a) — POW!/ZAP!/KRAK!/HEH,
/// mais "❝ Citar" opcional (recurso 5h). Tocar reage; tocar de novo troca/remove.
struct ReactionBarModifier: ViewModifier {
    @Binding var isPresented: Bool
    var onReact: (ReactionType) -> Void
    var onQuote: (() -> Void)? = nil
    var quoteLabel: String? = nil

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPresented ? 1.03 : 1)
            .shadow(color: isPresented ? MV.C.ink.opacity(0.3) : .clear, radius: isPresented ? 12 : 0, y: isPresented ? 6 : 0)
            .onLongPressGesture(minimumDuration: 0.35) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isPresented = true }
            }
            .overlay {
                if isPresented {
                    GeometryReader { geo in
                        ZStack {
                            Color.black.opacity(0.4) // "escurece a tela" — cobre uma área generosa ao redor do card
                                .frame(width: 2000, height: 2000)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                                .onTapGesture { withAnimation { isPresented = false } }

                            bar
                                .position(x: geo.size.width / 2, y: -34)
                        }
                    }
                    .zIndex(10)
                }
            }
    }

    private var bar: some View {
        HStack(spacing: 0) {
            if let onQuote {
                pill(label: quoteLabel ?? L10n.text("❝ Citar"), bg: MV.C.accent, fg: MV.C.ink) {
                    isPresented = false
                    onQuote()
                }
            }
            ForEach(ReactionType.allCases, id: \.self) { type in
                pill(label: type.rawValue, sub: type.subtitle, bg: type.color, fg: type.textColor) {
                    isPresented = false
                    onReact(type)
                }
            }
        }
        .padding(6)
        .background(MV.C.ink)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.lg))
        .overlay(RoundedRectangle(cornerRadius: MV.R.lg).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .background(RoundedRectangle(cornerRadius: MV.R.lg).fill(MV.C.marvel).offset(x: 3, y: 3))
        .fixedSize()
    }

    private func pill(label: String, sub: String? = nil, bg: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(label).font(MVFont.black(14)).foregroundStyle(fg)
                if let sub {
                    Text(sub).font(MVFont.body(8, weight: 700)).foregroundStyle(MV.C.paper)
                }
            }
            .frame(width: 64, height: sub != nil ? 60 : 44)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        }
        .buttonStyle(.plain)
        .padding(2)
    }
}

extension View {
    /// Segurar mostra a barra de reações (+ "Citar" se `onQuote` for passado).
    func reactionBar(isPresented: Binding<Bool>, onReact: @escaping (ReactionType) -> Void, onQuote: (() -> Void)? = nil, quoteLabel: String? = nil) -> some View {
        modifier(ReactionBarModifier(isPresented: isPresented, onReact: onReact, onQuote: onQuote, quoteLabel: quoteLabel))
    }
}

/// Linha de pílulas de reação pro rodapé do card (substitui o ♥ sozinho — recurso 5a).
struct ReactionPillsRow: View {
    let reviewID: String
    @Environment(AppStore.self) private var store

    var body: some View {
        let counts = store.reactionCounts(for: reviewID)
        let mine = store.userReaction(for: reviewID)
        if !counts.isEmpty {
            HStack(spacing: 6) {
                ForEach(counts, id: \.type) { entry in
                    let active = mine == entry.type
                    Text("\(entry.type.rawValue) \(entry.count)")
                        .font(MVFont.bold(11))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .foregroundStyle(active ? entry.type.textColor : MV.C.ink)
                        .background(active ? entry.type.color : MV.C.card)
                        .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(Capsule())
                        .onTapGesture { store.setReaction(entry.type, for: reviewID) }
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
    }
}
