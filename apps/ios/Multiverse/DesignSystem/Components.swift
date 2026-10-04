import SwiftUI

// MARK: - Card de gibi: fundo + borda 2pt ink + sombra dura deslocada

struct ComicCard: ViewModifier {
    var bg: Color = MV.C.card
    var radius: CGFloat = MV.R.xl
    var shadow: CGFloat = MV.Shadow.m
    var dashed = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(bg))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(MV.C.ink, style: StrokeStyle(lineWidth: MV.stroke, dash: dashed ? [6, 4] : []))
            )
            .background(
                RoundedRectangle(cornerRadius: radius).fill(shadow > 0 ? MV.C.shadow : .clear)
                    .offset(x: shadow, y: shadow)
            )
    }
}

extension View {
    func comicCard(bg: Color = MV.C.card, radius: CGFloat = MV.R.xl, shadow: CGFloat = MV.Shadow.m, dashed: Bool = false) -> some View {
        modifier(ComicCard(bg: bg, radius: radius, shadow: shadow, dashed: dashed))
    }
}

// MARK: - Retícula (halftone) — pontos de 1pt de raio a cada 6pt, ink 20%

struct Halftone: View {
    var spacing: CGFloat = 6
    var radius: CGFloat = 1.1
    var color: Color = MV.C.ink.opacity(0.2)

    var body: some View {
        Canvas { ctx, size in
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Capa real, com arte gráfica como fallback

struct PosterView: View {
    let item: Item
    let universe: Universe
    var width: CGFloat = 96
    var height: CGFloat = 144
    var radius: CGFloat = MV.R.md
    var titleSize: CGFloat = 12
    var showLabel = true
    var shadow: CGFloat = MV.Shadow.m

    var body: some View {
        let p = Logic.posterColors(item: item, universe: universe)
        ZStack(alignment: .topLeading) {
            p.bg
            Halftone()
            VStack(alignment: .leading) {
                if showLabel {
                    Text(L10n.format("%1$@ · %2$@", String(describing: item.type == "Personagem" ? L10n.text("RETRATO") : L10n.text("CAPA")), String(describing: L10n.text(item.type).uppercased())))
                        .font(MVFont.mono).foregroundStyle(p.fg)
                }
                Spacer(minLength: 0)
                Text(item.title.uppercased())
                    .font(MVFont.archivo(titleSize, weight: 900, width: 95))
                    .lineSpacing(-2)
                    .foregroundStyle(p.fg)
                    .minimumScaleFactor(0.7)
            }
            .padding(8)
        }
        .frame(width: width, height: height)
        .overlay { CatalogCoverOverlay(cover: item.cover, width: width, height: height) }
        .comicCard(bg: p.bg, radius: radius, shadow: shadow)
    }
}

// MARK: - Avatar (círculo com iniciais, borda ink)

struct AvatarView: View {
    let user: User
    var size: CGFloat = 28
    var border: CGFloat = MV.stroke

    var body: some View {
        ProfileAvatarFace(name: user.name, color: user.avatarColor, avatarID: user.avatarID, size: size)
            .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: border))
    }
}

// MARK: - Selo de universo ao lado do nome ("TERRA-616")

struct BadgeChip: View {
    let label: String
    let universe: Universe
    var body: some View {
        Text(label.uppercased())
            .font(MVFont.black(8)).tracking(0.5)
            .padding(.horizontal, 4)
            .foregroundStyle(Color(hex: universe.ink))
            .background(RoundedRectangle(cornerRadius: MV.R.xs).fill(Color(hex: universe.c)))
            .overlay(RoundedRectangle(cornerRadius: MV.R.xs).strokeBorder(MV.C.ink, lineWidth: 1.5))
            .fixedSize()
    }
}

// MARK: - Pílula (curtir, comentar, filtros)

struct PillButton: View {
    let title: String
    var active = false
    var activeBg: Color = MV.C.ink
    var activeFg: Color = MV.C.paper
    var size: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(MVFont.bold(size))
                .padding(.horizontal, 11).padding(.vertical, 5)
                .foregroundStyle(active ? activeFg : MV.C.ink)
                .background(Capsule().fill(active ? activeBg : MV.C.card))
                .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Estrelas (★★★★½) na cor do universo com contorno ink

struct StarsText: View {
    let rating: Double
    let color: Color
    var size: CGFloat = 15
    var body: some View {
        Text(Logic.stars(rating))
            .font(MVFont.black(size)).tracking(1)
            .foregroundStyle(color)
            .shadow(color: MV.C.ink, radius: 0, x: 0.5, y: 0.5)
    }
}

// MARK: - Barra de progresso de gibi

struct ComicProgress: View {
    let value: Double // 0...1
    let fill: Color
    var height: CGFloat = 16
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                MV.C.card
                Rectangle().fill(fill).frame(width: g.size.width * value)
                    .overlay(alignment: .trailing) { Rectangle().fill(MV.C.ink).frame(width: MV.stroke) }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
    }
}

// MARK: - Onomatopeia (POW! BAM! ZAP! KRAK! BOOM!)
// Uso: BurstCenter() injetado no ambiente; BurstOverlay() num ZStack por cima da tela;
// nos botões: use GeometryReader/coordinateSpace "screen" pra achar o ponto e chamar burst.fire(...)

@MainActor
@Observable
final class BurstCenter {
    struct Burst: Identifiable, Equatable {
        let id = UUID(); let text: String; let color: Color; let textColor: Color; let point: CGPoint
    }
    var current: Burst?
    private var resetTask: Task<Void, Never>?

    func fire(_ text: String, _ color: Color, textColor: Color = MV.C.paper, at point: CGPoint) {
        let b = Burst(text: text, color: color, textColor: textColor, point: point)
        current = b
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.75))
            guard !Task.isCancelled else { return }
            if self?.current?.id == b.id { self?.current = nil }
        }
    }
}

struct BurstOverlay: View {
    @Environment(BurstCenter.self) private var center
    var body: some View {
        ZStack {
            if let b = center.current { BurstView(burst: b).id(b.id) }
        }
        .allowsHitTesting(false)
    }
}

private struct BurstView: View {
    let burst: BurstCenter.Burst
    @State private var scale: CGFloat = 0.3
    @State private var rot: Double = -14
    @State private var opacity: Double = 0
    @State private var dy: CGFloat = 0

    var body: some View {
        Text(burst.text)
            .font(MVFont.display(20))
            .foregroundStyle(burst.textColor)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .comicCard(bg: burst.color, radius: MV.R.sm, shadow: MV.Shadow.m)
            .scaleEffect(scale).rotationEffect(.degrees(rot)).opacity(opacity)
            .position(x: burst.point.x, y: burst.point.y - 24 + dy)
            .onAppear {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { scale = 1.2; rot = -6; opacity = 1 }
                withAnimation(.easeOut(duration: 0.55).delay(0.2)) { scale = 1; rot = -4; opacity = 0; dy = -30 }
            }
    }
}
