import SwiftUI

/// Tab bar customizada: Início, Busca, botão + central, Biblioteca, Perfil.
/// Avisos saiu daqui — agora é o sino no topo da Home (ver `AppStore.openNotifications()`).
struct CustomTabBar: View {
    @Environment(AppStore.self) private var store
    var onPlusTapped: () -> Void

    private let items: [(AppTab, String)] = [(.home, L10n.text("Início")), (.search, L10n.text("Busca")), (.library, L10n.text("Biblioteca")), (.profile, L10n.text("Perfil"))]

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                tabButton(items[0])
                tabButton(items[1])
                Spacer().frame(width: 54 + 16)
                tabButton(items[2])
                tabButton(items[3])
            }
            .frame(height: 88)
            .frame(maxWidth: .infinity)
            .background(MV.C.paper)
            .overlay(alignment: .top) { Rectangle().fill(MV.C.ink).frame(height: MV.stroke) }

            Button(action: onPlusTapped) {
                Text("+")
                    .font(MVFont.black(28))
                    .foregroundStyle(MV.C.card)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(MV.C.marvel))
                    .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .background(Circle().fill(MV.C.shadow).offset(x: MV.Shadow.m, y: MV.Shadow.m))
            }
            .buttonStyle(.plain)
            .offset(y: -18)
            .accessibilityLabel(L10n.text("Registrar"))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func tabButton(_ entry: (AppTab, String)) -> some View {
        let (t, label) = entry
        let active = store.tab == t
        Button {
            store.goToTab(t)
        } label: {
            Text(label)
                .font(MVFont.archivo(12, weight: 800, width: t == .library ? 90 : 100))
                .textCase(.uppercase)
                .tracking(t == .library ? 0 : 0.2)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .allowsTightening(true)
                .foregroundStyle(active ? MV.C.paper : MV.C.ink)
                .frame(maxWidth: 70, minHeight: 40, maxHeight: 40)
                .background(active ? MV.C.ink : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}
