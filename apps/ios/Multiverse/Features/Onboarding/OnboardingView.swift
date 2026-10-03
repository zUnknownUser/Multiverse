import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            MV.C.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBars
                    .padding(.top, 62)
                    .padding(.horizontal, MV.pad)

                Group {
                    switch store.onboardingPhase {
                    case .step1: OnboardingStep1View()
                    case .step2: OnboardingStep2View()
                    case .step3: OnboardingStep3View()
                    case .loading: OnboardingLoadingView()
                    }
                }
                .frame(maxHeight: .infinity)

                if store.onboardingPhase != .loading {
                    footerButtons
                        .padding(.horizontal, MV.pad)
                        .padding(.bottom, 34)
                }
            }

            BurstOverlay()
            ToastOverlay()
        }
        .coordinateSpace(name: "screen")
    }

    private var progressBars: some View {
        HStack(spacing: 8) {
            ForEach(1...store.onboardingStepCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(barFilled(i) ? MV.C.ink : Color.clear)
                    .frame(height: 6)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(MV.C.ink, lineWidth: 1.5))
            }
        }
    }

    private func barFilled(_ i: Int) -> Bool {
        switch store.onboardingPhase {
        case .loading: return true
        case .step1: return i <= 1
        case .step2: return i <= 2
        case .step3: return i <= 3
        }
    }

    private var canGoBack: Bool {
        store.onboardingPhase == .step2 || store.onboardingPhase == .step3
    }

    private var isCTAEnabled: Bool {
        store.canAdvanceOnboarding
    }

    private var ctaLabel: String {
        switch store.onboardingPhase {
        case .step1: return L10n.text("Continuar")
        case .step2:
            if store.onboardingStepCount == 2 { return L10n.text("Começar a explorar") }
            let n = store.onboardingConsumablePicks().filter { store.isSeen($0.id) }.count
            return n > 0 ? L10n.text("Continuar") : L10n.text("Pular")
        case .step3:
            let n = store.onboardingSelectedFollowCount
            if store.onboardingFollowingOptional && n == 0 { return L10n.text("Pular por enquanto") }
            return n >= store.minimumOnboardingFollows ? L10n.text("Montar meu feed") : L10n.format("Siga mais %1$@", String(describing: store.minimumOnboardingFollows - n))
        case .loading: return ""
        }
    }

    private var footerButtons: some View {
        HStack(spacing: 12) {
            if canGoBack {
                Button { store.backOnboarding() } label: {
                    Text("←")
                        .font(MVFont.black(20))
                        .foregroundStyle(MV.C.ink)
                        .frame(width: 54, height: 54)
                        .background(MV.C.card)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                }
                .buttonStyle(.plain)
            }
            Text(ctaLabel)
                .font(MVFont.bold(15))
                .foregroundStyle(isCTAEnabled ? MV.C.card : MV.C.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(isCTAEnabled ? MV.C.marvel : MV.C.desk)
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                .background(
                    RoundedRectangle(cornerRadius: MV.R.md)
                        .fill(isCTAEnabled ? MV.C.ink : .clear)
                        .offset(x: MV.Shadow.m, y: MV.Shadow.m)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isCTAEnabled else { return }
                    store.advanceOnboarding()
                }
        }
    }
}
