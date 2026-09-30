import SwiftUI

/// "Mapa de conexões" da Obra: nó central "AQUI" ligado a até 6 itens relacionados,
/// dispostos em elipse. Ver `AppStore.connectedItems(for:)`.
struct ConnectionMapView: View {
    let center: Item
    let connected: [Item]
    @Environment(AppStore.self) private var store

    private let ellipseRadiusX: CGFloat = 118
    private let ellipseRadiusY: CGFloat = 84
    private let centerNodeSize: CGFloat = 62
    private let nodeSize: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            let mid = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let positions = nodePositions(around: mid, count: connected.count)

            ZStack {
                ForEach(Array(connected.enumerated()), id: \.offset) { index, _ in
                    Path { path in
                        path.move(to: mid)
                        path.addLine(to: positions[index])
                    }
                    .stroke(MV.C.ink, lineWidth: 2)
                }

                Text(L10n.text("AQUI"))
                    .font(MVFont.black(11))
                    .foregroundStyle(MV.C.paper)
                    .frame(width: centerNodeSize, height: centerNodeSize)
                    .background(Circle().fill(MV.C.ink))
                    .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .position(mid)

                ForEach(Array(connected.enumerated()), id: \.offset) { index, item in
                    ConnectionNode(item: item, size: nodeSize)
                        .position(positions[index])
                }
            }
        }
        .frame(height: 270)
        .background(MV.C.card)
        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, style: StrokeStyle(lineWidth: MV.stroke, dash: [10, 6])))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
    }

    private func nodePositions(around mid: CGPoint, count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            let extraOffset = count == 2 ? 90.0 : 0
            let angle = (-90 + Double(i) * 360 / Double(count) + extraOffset) * .pi / 180
            return CGPoint(x: mid.x + cos(angle) * ellipseRadiusX, y: mid.y + sin(angle) * ellipseRadiusY)
        }
    }
}

private struct ConnectionNode: View {
    let item: Item
    let size: CGFloat
    @Environment(AppStore.self) private var store

    var body: some View {
        let uni = store.universe(of: item)
        let p = Logic.posterColors(item: item, universe: uni)
        let radius: CGFloat = item.type == "Personagem" ? size / 2 : (item.type == "Evento" ? 4 : 8)

        Button { store.push(.item(item.id)) } label: {
            VStack(spacing: 4) {
                ZStack { p.bg; Halftone() }
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: radius))
                    .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                Text(item.title)
                    .font(MVFont.bold(9))
                    .foregroundStyle(MV.C.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(MV.C.card)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 84)
    }
}
