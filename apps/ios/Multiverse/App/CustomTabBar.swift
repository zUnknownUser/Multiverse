import SwiftUI

/// Tab bar customizada: Início, Busca, botão + central, Clubes, Perfil.
/// Avisos saiu daqui — agora é o sino no topo da Home (ver `AppStore.openNotifications()`).
struct CustomTabBar: View {
    @Environment(AppStore.self) private var store
    @Environment(BurstCenter.self) private var burst
    var onPlusTapped: () -> Void

    private let items: [(AppTab, String)] = [(.home, "Início"), (.search, "Busca"), (.clubs, "Clubes"), (.profile, "Perfil")]

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
            .accessibilityLabel("Registrar")
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
                .kicker(11)
                .foregroundStyle(active ? MV.C.paper : MV.C.ink)
                .frame(width: 70, height: 40)
                .background(active ? MV.C.ink : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}
