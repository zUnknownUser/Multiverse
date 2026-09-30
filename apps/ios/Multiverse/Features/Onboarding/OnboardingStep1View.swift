import SwiftUI

struct OnboardingStep1View: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bem-vindo ao Multiverse · 1 de 3").kicker(11).foregroundStyle(MV.C.muted)
                    Text("Quais universos são seus?")
                        .font(MVFont.display(30, width: 120))
                        .lineSpacing(-4)
                        .foregroundStyle(MV.C.ink)
                    Text("Escolha onde você quer registrar, avaliar e discutir cânone.")
                        .font(MVFont.body(14)).foregroundStyle(MV.C.muted)
                }

                VStack(spacing: 10) {
                    ForEach(store.universes) { u in
                        UniverseSelectRow(universe: u)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(StaticContent.comingSoonUniverses, id: \.self) { name in
                        ComingSoonRow(name: name)
                    }
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.top, 18)
        }
        .scrollIndicators(.hidden)
    }
}

private struct UniverseSelectRow: View {
    let universe: Universe
    @Environment(AppStore.self) private var store

    var body: some View {
        let selected = store.onboardingUniverses.contains(universe.id)
        HStack {
            Text(universe.name.uppercased())
                .font(MVFont.archivo(22, weight: 900, width: 120))
                .foregroundStyle(selected ? universe.inkColor : MV.C.ink)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Logic.fmt(universe.members)) loristas")
                    .font(MVFont.body(11, weight: 700))
                    .foregroundStyle(selected ? universe.inkColor.opacity(0.85) : MV.C.muted)
                Text("\(Logic.fmt(universe.total)) itens")
                    .font(MVFont.body(11, weight: 700))
                    .foregroundStyle(selected ? universe.inkColor.opacity(0.85) : MV.C.muted)
            }
            ZStack {
                Circle().fill(selected ? MV.C.ink.opacity(0.15) : MV.C.paper)
                Text(selected ? "✓" : "+")
                    .font(MVFont.black(16))
                    .foregroundStyle(selected ? universe.inkColor : MV.C.ink)
            }
            .frame(width: 30, height: 30)
            .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: 1.5))
            .padding(.leading, 10)
        }
        .padding(.horizontal, 14)
        .frame(height: 72)
        .background(selected ? universe.color : MV.C.card)
        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
        .background(
            RoundedRectangle(cornerRadius: MV.R.xl)
                .fill(selected ? MV.C.ink : .clear)
                .offset(x: selected ? 4 : 0, y: selected ? 4 : 0)
        )
        .offset(x: selected ? -2 : 0, y: selected ? -2 : 0)
        .burstOnTap("POW!", color: universe.color, textColor: universe.inkColor, when: !selected) {
            store.toggleOnboardingUniverse(universe.id)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: selected)
    }
}

private struct ComingSoonRow: View {
    let name: String
    var body: some View {
        HStack {
            Text(name.uppercased())
                .font(MVFont.archivo(16, weight: 900, width: 115))
                .foregroundStyle(MV.C.muted)
            Spacer()
            Text("EM BREVE")
                .font(MVFont.black(9)).tracking(0.6)
                .foregroundStyle(MV.C.muted)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(style: StrokeStyle(lineWidth: MV.stroke, dash: [6, 4])).foregroundStyle(MV.C.muted.opacity(0.6)))
    }
}
