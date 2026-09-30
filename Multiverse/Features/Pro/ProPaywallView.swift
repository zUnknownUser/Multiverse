import SwiftUI
import StoreKit

/// Paywall do Multiverse Pro — recurso 4a. StoreKit 2 de verdade; testável no Simulator
/// via `Configuration/Products.storekit` (ver README de setup no Mac).
struct ProPaywallView: View {
    @Environment(ProStore.self) private var proStore
    @Environment(\.dismiss) private var dismiss

    private let features: [(title: String, subtitle: String)] = [
        ("Estatísticas avançadas", "horas, notas, hábitos"),
        ("Wrapped anual", "o resumo do seu ano inteiro"),
        ("Temas", "Noir, Pergaminho e Gibi clássico"),
        ("Selos e molduras exclusivos", "no seu nome em todo lugar"),
        ("Listas e clubes sem limite", ""),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { dismiss() } label: {
                        Text("✕").font(.system(size: 20, weight: .bold)).foregroundStyle(MV.C.ink)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        Task { await proStore.restorePurchases() }
                    } label: {
                        Text("Restaurar compra").font(MVFont.bold(13)).underline().foregroundStyle(MV.C.ink)
                    }
                    .buttonStyle(.plain)
                }

                hero

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(features, id: \.title) { feature in
                        HStack(spacing: 12) {
                            ZStack { Circle().fill(MV.C.ink); Text("✓").font(MVFont.black(11)).foregroundStyle(MV.C.wow) }
                                .frame(width: 26, height: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(feature.title).font(MVFont.bold(15)).foregroundStyle(MV.C.ink)
                                if !feature.subtitle.isEmpty {
                                    Text(feature.subtitle).font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                                }
                            }
                        }
                    }
                }

                if proStore.isLoadingProducts {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                } else if proStore.products.isEmpty {
                    Text("Configure `Configuration/Products.storekit` no scheme do Xcode pra testar as compras (ver README).")
                        .font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                        .padding(14).comicCard(shadow: 0, dashed: true)
                } else {
                    plansRow
                }

                if let error = proStore.purchaseError {
                    Text(error).font(MVFont.bold(12)).foregroundStyle(MV.C.marvel)
                }

                Spacer(minLength: 8)

                Text("TESTAR 7 DIAS GRÁTIS")
                    .font(MVFont.bold(15))
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .foregroundStyle(MV.C.paper)
                    .background(MV.C.ink)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .background(RoundedRectangle(cornerRadius: MV.R.md).fill(MV.C.marvel).offset(x: MV.Shadow.m, y: MV.Shadow.m))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard let annual = proStore.products.first(where: { $0.id == ProStore.annualID }) else { return }
                        Task { await proStore.purchase(annual) }
                    }

                Text("Cancele quando quiser. Anúncio no feed? Nunca.")
                    .font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(MV.pad)
            .padding(.bottom, 24)
        }
        .background(MV.C.paper.ignoresSafeArea())
        .onChange(of: proStore.isPro) { _, isPro in if isPro { dismiss() } }
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            MV.C.marvel
            Halftone(color: MV.C.paper.opacity(0.14))
            VStack(alignment: .leading, spacing: 10) {
                Text("MULTI-\nVERSE").font(MVFont.display(40, width: 122)).lineSpacing(-8).foregroundStyle(MV.C.paper)
                Text("PRO")
                    .font(MVFont.display(26))
                    .foregroundStyle(MV.C.ink)
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .background(MV.C.wow)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.sm))
                    .rotationEffect(.degrees(-4))
                Text("Pra quem leva o cânone a sério.").font(MVFont.bold(15)).foregroundStyle(MV.C.paper)
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xxl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xxl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .background(RoundedRectangle(cornerRadius: MV.R.xxl).fill(MV.C.shadow).offset(x: MV.Shadow.l, y: MV.Shadow.l))
    }

    private var plansRow: some View {
        HStack(spacing: 10) {
            ForEach(proStore.products) { product in
                planCard(product)
            }
        }
    }

    private func planCard(_ product: Product) -> some View {
        let isAnnual = product.id == ProStore.annualID
        return VStack(alignment: .leading, spacing: 4) {
            if isAnnual {
                Text("2 MESES GRÁTIS")
                    .font(MVFont.black(9)).tracking(0.3)
                    .foregroundStyle(MV.C.paper)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(MV.C.ink)
            }
            Text(isAnnual ? "ANUAL ✓" : "MENSAL").font(MVFont.bold(12)).foregroundStyle(MV.C.ink)
            Text(product.displayPrice).font(MVFont.black(26)).foregroundStyle(MV.C.ink)
            Text(isAnnual ? "por mês, cobrado anual" : "por mês").font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isAnnual ? MV.C.wow : MV.C.card)
        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        .background(RoundedRectangle(cornerRadius: MV.R.md).fill(MV.C.shadow).offset(x: MV.Shadow.s, y: MV.Shadow.s))
        .contentShape(Rectangle())
        .onTapGesture { Task { await proStore.purchase(product) } }
    }
}
