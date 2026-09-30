import SwiftUI

/// Teoria confirmada/refutada — recurso 1f.
struct TheoryDetailView: View {
    let theoryID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: Image?

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            if let theory = store.theories.first(where: { $0.id == theoryID }), let user = store.user(theory.userID) {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack(alignment: .topTrailing) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                AvatarView(user: user, size: 30)
                                Text(L10n.format("%1$@ · postada há %2$@ dias", String(describing: user.name), String(describing: theory.postedDaysAgo)))
                                    .font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                            }
                            Text(theory.text.uppercased()).font(MVFont.black(22)).foregroundStyle(MV.C.ink)
                        }
                        .padding(16)
                        .comicCard(shadow: MV.Shadow.s)

                        stamp(theory: theory)
                    }
                    .padding(.top, 20)

                    if theory.status == .confirmed, let before = theory.accuracyBefore, let after = theory.accuracyAfter {
                        pointsCard
                        accuracyCard(before: before, after: after)
                    }

                    if let title = theory.resolutionTitle {
                        resolvedByCard(title: title, note: theory.resolutionNote, confirmed: theory.status == .confirmed)
                    }

                    if theory.status == .confirmed {
                        shareButton
                    }
                }
                .padding(.horizontal, MV.pad)
                .padding(.bottom, 24)
                .task { shareImage = await renderShareImage(theory: theory, user: user) }
            }
        }
    }

    @ViewBuilder
    private func stamp(theory: Theory) -> some View {
        let color = theory.status == .confirmed ? MV.C.dc : MV.C.marvel
        Text(theory.status == .confirmed ? L10n.text("CONFIRMADA!") : L10n.text("REFUTADA!"))
            .font(MVFont.display(20))
            .foregroundStyle(MV.C.paper)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(color)
            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
            .background(RoundedRectangle(cornerRadius: MV.R.md).fill(MV.C.shadow).offset(x: 3, y: 3))
            .rotationEffect(.degrees(8))
            .offset(x: 4, y: -14)
    }

    private var pointsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("VOCÊ VOTOU PLAUSÍVEL")).kicker(11).foregroundStyle(MV.C.paper.opacity(0.85))
            Text("+40").font(MVFont.black(56)).foregroundStyle(MV.C.paper)
                + Text(L10n.text(" PONTOS DE LORE")).font(MVFont.bold(16)).foregroundStyle(MV.C.paper)
            Text(L10n.format("Junto com %1$@ loristas.", String(describing: Logic.fmt(1204))))
                .font(MVFont.body(13, weight: 600)).foregroundStyle(MV.C.paper.opacity(0.9))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MV.C.dc)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .background(RoundedRectangle(cornerRadius: MV.R.xl).fill(MV.C.shadow).offset(x: MV.Shadow.s, y: MV.Shadow.s))
    }

    private func accuracyCard(before: Int, after: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("SEU ACERTO EM TEORIAS")).kicker(11).foregroundStyle(MV.C.muted)
            HStack(alignment: .lastTextBaseline) {
                Text("\(before)%").font(MVFont.black(30)).foregroundStyle(MV.C.muted)
                Text("→").font(MVFont.black(20)).foregroundStyle(MV.C.muted)
                Text("\(after)%").font(MVFont.black(30)).foregroundStyle(MV.C.dc)
                Spacer()
                Text(L10n.text("top 12%\nde Azeroth")).font(MVFont.bold(11)).multilineTextAlignment(.trailing).foregroundStyle(MV.C.muted)
            }
            ComicProgress(value: Double(after) / 100, fill: MV.C.dc, height: 8)
        }
        .padding(14)
        .comicCard(shadow: MV.Shadow.s)
    }

    private func resolvedByCard(title: String, note: String?, confirmed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(confirmed ? L10n.text("CONFIRMADA POR") : L10n.text("REFUTADA POR")).kicker(11).foregroundStyle(MV.C.muted)
            HStack(spacing: 12) {
                ZStack { MV.C.wow; Halftone() }
                    .frame(width: 52, height: 78)
                    .comicCard(bg: MV.C.wow, radius: MV.R.md, shadow: MV.Shadow.s)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(MVFont.bold(15)).foregroundStyle(MV.C.ink)
                    if let note { Text(note).font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.muted) }
                }
                Spacer()
            }
        }
        .padding(14)
        .comicCard(shadow: MV.Shadow.s)
    }

    private var shareButton: some View {
        Group {
            if let shareImage {
                ShareLink(item: shareImage, preview: SharePreview(L10n.text("Eu avisei"), image: shareImage)) { shareLabel }
            } else {
                shareLabel
            }
        }
    }

    private var shareLabel: some View {
        Text(L10n.text("COMPARTILHAR \"EU AVISEI\""))
            .font(MVFont.bold(14))
            .frame(maxWidth: .infinity).frame(height: 54)
            .foregroundStyle(MV.C.paper)
            .background(MV.C.ink)
            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
            .background(RoundedRectangle(cornerRadius: MV.R.md).fill(MV.C.dc).offset(x: MV.Shadow.m, y: MV.Shadow.m))
    }

    @MainActor
    private func renderShareImage(theory: Theory, user: User) async -> Image? {
        let renderer = ImageRenderer(content: TheoryShareCard(theory: theory, authorName: user.name))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}

private struct TheoryShareCard: View {
    let theory: Theory
    let authorName: String

    var body: some View {
        ZStack {
            MV.C.dc
            Halftone(spacing: 8, radius: 1.4, color: MV.C.paper.opacity(0.18))
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.text("EU AVISEI")).font(MVFont.display(48, width: 122)).foregroundStyle(MV.C.paper)
                Text(theory.text.uppercased()).font(MVFont.black(26)).foregroundStyle(MV.C.paper)
                Spacer()
                Text(L10n.format("CONFIRMADA · @%1$@", String(describing: authorName))).font(MVFont.bold(16)).foregroundStyle(MV.C.paper.opacity(0.85))
                Text("MULTIVERSE").font(MVFont.black(18)).foregroundStyle(MV.C.paper)
            }
            .padding(40)
        }
        .frame(width: 360, height: 640)
    }
}
