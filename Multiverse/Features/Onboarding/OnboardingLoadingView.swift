import SwiftUI

struct OnboardingLoadingView: View {
    @Environment(AppStore.self) private var store
    @State private var pulse = false
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let selected = store.onboardingUniverses.isEmpty ? ["wow"] : Array(store.onboardingUniverses)
        let colors = selected.compactMap { store.universe($0)?.color }
        let nFol = store.friendsCount

        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 10) {
                Text("MONTANDO SEU\nMULTIVERSO")
                    .font(MVFont.display(36, width: 120))
                    .lineSpacing(-8)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MV.C.ink)
                Text("Puxando reviews, votos e listas de \(nFol) loristas em \(max(1, selected.count)) universo\(selected.count > 1 ? "s" : "")…")
                    .font(MVFont.body(13, weight: 600))
                    .foregroundStyle(MV.C.muted)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: MV.R.md)
                        .fill(colors[i % colors.count])
                        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .opacity(pulse ? 1 : 0.35)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(Double(i) * 0.12), value: pulse)
                }
            }
            .padding(.horizontal, MV.pad)
            Spacer()
        }
        .onAppear { pulse = true }
    }
}
