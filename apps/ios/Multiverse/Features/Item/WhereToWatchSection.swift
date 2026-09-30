import SwiftUI

/// "Onde assistir" — recurso 4c. Dados mockados em `recursos-data.json`, via
/// `AppStore.loadWatchAvailability(for:)` → `MultiverseRepository.fetchWatchAvailability`.
struct WhereToWatchSection: View {
    let itemID: String
    @Environment(AppStore.self) private var store
    @State private var notifyOnServiceIOwn = true

    var body: some View {
        if let availability = store.watchAvailabilityByItem[itemID] {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L10n.text("ONDE ASSISTIR")).font(MVFont.section(18)).foregroundStyle(MV.C.ink)
                    Spacer()
                    Text(L10n.text("BRASIL")).font(MVFont.bold(10))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .foregroundStyle(MV.C.ink)
                        .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                }

                VStack(spacing: 10) {
                    ForEach(availability.options) { option in
                        WatchOptionRow(option: option)
                    }
                }

                if !availability.readFirst.isEmpty {
                    Text(L10n.text("LEIA ANTES")).font(MVFont.section(16)).foregroundStyle(MV.C.ink)
                    VStack(spacing: 10) {
                        ForEach(availability.readFirst) { option in
                            ReadFirstRow(option: option)
                        }
                    }
                }

                HStack {
                    Text(L10n.text("Me avise quando entrar num serviço que eu assino"))
                        .font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                    Spacer()
                    Toggle("", isOn: $notifyOnServiceIOwn).labelsHidden().tint(MV.C.wow)
                }
                .padding(14)
                .comicCard(shadow: MV.Shadow.s)

                Text(L10n.text("LINK DE AFILIADO · o Multiverse pode ganhar uma comissão, sem custo extra pra você. Isso ajuda a manter o app sem anúncios."))
                    .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
            }
        } else {
            Color.clear.frame(height: 0).task { await store.loadWatchAvailability(for: itemID) }
        }
    }
}

private struct WatchOptionRow: View {
    let option: WatchOption
    var body: some View {
        HStack(spacing: 12) {
            ZStack { Color(hex: option.colorHex); Text(option.initials).font(MVFont.black(13)).foregroundStyle(Logic.inkOn(hex: option.colorHex)) }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: MV.R.sm))
                .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            VStack(alignment: .leading, spacing: 2) {
                Text(option.service).font(MVFont.bold(15)).foregroundStyle(MV.C.ink)
                Text(option.note).font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
            }
            Spacer()
            Text(L10n.text(option.actionLabel))
                .font(MVFont.bold(12))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .foregroundStyle(option.actionLabel == "ASSISTIR" ? MV.C.paper : MV.C.ink)
                .background(option.actionLabel == "ASSISTIR" ? MV.C.ink : MV.C.wow)
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        }
        .padding(12)
        .comicCard(shadow: MV.Shadow.s)
    }
}

private struct ReadFirstRow: View {
    let option: ReadFirstOption
    var body: some View {
        HStack(spacing: 12) {
            ZStack { Color(hex: option.colorHex); Halftone() }
                .frame(width: 44, height: 66)
                .comicCard(bg: Color(hex: option.colorHex), radius: MV.R.sm, shadow: MV.Shadow.s)
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title).font(MVFont.bold(15)).foregroundStyle(MV.C.ink)
                Text(option.subtitle + " · " + option.note).font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
            }
            Spacer()
            Text(L10n.text(option.actionLabel))
                .font(MVFont.bold(12))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .foregroundStyle(MV.C.ink)
                .background(MV.C.wow)
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        }
        .padding(12)
        .comicCard(shadow: MV.Shadow.s)
    }
}
