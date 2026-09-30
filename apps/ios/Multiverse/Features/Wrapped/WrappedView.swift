import SwiftUI

struct WrappedView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: Image?

    var body: some View {
        let data = store.wrappedData()
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(spacing: 12) {
                heroCard
                HStack(alignment: .top, spacing: 12) {
                    countCard(data: data).frame(maxWidth: .infinity)
                    hoursCard(data: data).frame(width: 130)
                }
                universeCard(data: data)
                if let top = data.topItem { topRatedCard(item: top, stars: data.topStars) }
                archetypeCard(data: data)
                if !data.topReviewText.isEmpty { topReviewCard(data: data) }
                shareButton
            }
            .padding(.horizontal, MV.pad)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .task { shareImage = await renderShareImage(data: data) }
    }

    private var heroCard: some View {
        ZStack(alignment: .leading) {
            MV.C.marvel
            Halftone(spacing: 7, color: MV.C.paper.opacity(0.16))
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("MULTIVERSE WRAPPED · SET 2026")).kicker(11).foregroundStyle(MV.C.paper.opacity(0.85))
                Text(L10n.text("SEU MÊS\nNO CÂNONE")).font(MVFont.display(40, width: 122)).lineSpacing(-8).foregroundStyle(MV.C.paper)
                if let handle = store.user(store.meID)?.handle {
                    Text(handle).font(MVFont.bold(14)).foregroundStyle(MV.C.paper.opacity(0.9))
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xxl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xxl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .background(RoundedRectangle(cornerRadius: MV.R.xxl).fill(MV.C.shadow).offset(x: MV.Shadow.m, y: MV.Shadow.m))
    }

    private func countCard(data: WrappedData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("REGISTROS")).kicker(10).foregroundStyle(MV.C.muted)
            Text("\(data.logCount)").font(MVFont.black(64)).foregroundStyle(MV.C.ink)
            Text(data.deltaLabel).font(MVFont.bold(12)).foregroundStyle(MV.C.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .comicCard(shadow: MV.Shadow.m)
    }

    private func hoursCard(data: WrappedData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("HORAS DE LORE")).kicker(9).foregroundStyle(MV.C.paper.opacity(0.75))
            Text("\(data.hours)").font(MVFont.black(38)).foregroundStyle(MV.C.paper)
            Text(data.hoursNote).font(MVFont.body(9, weight: 700)).foregroundStyle(MV.C.paper.opacity(0.85))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MV.C.ink)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
    }

    private func universeCard(data: WrappedData) -> some View {
        ZStack(alignment: .leading) {
            data.universe.color
            Halftone(color: data.universe.inkColor.opacity(0.18))
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("UNIVERSO DO MÊS")).kicker(10).foregroundStyle(data.universe.inkColor.opacity(0.85))
                Text(data.universe.name.uppercased()).font(MVFont.display(36, width: 122)).foregroundStyle(data.universe.inkColor)
                Text(data.universeNote).font(MVFont.bold(12)).foregroundStyle(data.universe.inkColor.opacity(0.9))
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xxl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xxl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
    }

    private func topRatedCard(item: Item, stars: Double) -> some View {
        Button { store.push(.item(item.id)) } label: {
            HStack(spacing: 12) {
                PosterView(item: item, universe: store.universe(of: item), width: 58, height: 87, titleSize: 9)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("NOTA MAIS ALTA")).kicker(10).foregroundStyle(MV.C.muted)
                    Text(item.title).font(MVFont.bold(16)).foregroundStyle(MV.C.ink)
                    StarsText(rating: stars, color: store.universe(of: item).color, size: 16)
                }
                Spacer()
            }
            .padding(14)
            .comicCard(shadow: MV.Shadow.s)
        }
        .buttonStyle(.plain)
    }

    private func archetypeCard(data: WrappedData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("SEU ARQUÉTIPO")).kicker(11).foregroundStyle(MV.C.paper.opacity(0.8))
            Text(data.archetypeTitle.uppercased()).font(MVFont.display(24, width: 118)).foregroundStyle(MV.C.paper)
            Text(data.archetypeNote).font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.paper.opacity(0.9))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MV.C.dc)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
    }

    private func topReviewCard(data: WrappedData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("REVIEW MAIS CURTIDA")).kicker(11).foregroundStyle(MV.C.muted)
            Text("“\(data.topReviewText)”").font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)
            HStack {
                Text("♥ \(Logic.fmt(data.topReviewLikes))").font(MVFont.bold(12)).foregroundStyle(MV.C.marvel)
                Spacer()
                Text(data.topReviewItemTitle).font(MVFont.bold(12)).foregroundStyle(MV.C.muted)
            }
        }
        .padding(16)
        .comicCard(shadow: MV.Shadow.s)
    }

    private var shareButton: some View {
        Group {
            if let shareImage {
                ShareLink(item: shareImage, preview: SharePreview("Multiverse Wrapped", image: shareImage)) {
                    shareButtonLabel
                }
            } else {
                shareButtonLabel
            }
        }
    }

    private var shareButtonLabel: some View {
        Text(L10n.text("COMPARTILHAR NOS STORIES"))
            .font(MVFont.bold(14))
            .frame(maxWidth: .infinity).frame(height: 54)
            .foregroundStyle(MV.C.paper)
            .background(MV.C.ink)
            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
            .background(RoundedRectangle(cornerRadius: MV.R.md).fill(MV.C.marvel).offset(x: MV.Shadow.m, y: MV.Shadow.m))
    }

    @MainActor
    private func renderShareImage(data: WrappedData) async -> Image? {
        let renderer = ImageRenderer(content: WrappedShareCard(data: data, handle: store.user(store.meID)?.handle ?? ""))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}
