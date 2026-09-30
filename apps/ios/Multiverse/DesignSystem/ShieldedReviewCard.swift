import SwiftUI

/// Substitui `FeedReviewCard` quando a review é sobre um item à frente do ponto do
/// usuário na timeline do universo — Escudo de Spoiler (ver `AppStore.isShieldedReview`).
struct ShieldedReviewCard: View {
    let review: Review
    @Environment(AppStore.self) private var store

    var body: some View {
        guard let user = store.user(review.user), let item = store.item(review.item) else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    AvatarView(user: user, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name).font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                        Text(L10n.text("avaliou algo depois do seu ponto")).font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                    }
                    Spacer(minLength: 8)
                    Text(L10n.text("◆ ESCUDO"))
                        .font(MVFont.black(10)).tracking(0.4)
                        .foregroundStyle(MV.C.card)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(MV.C.dc)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.sm))
                }
                .padding(12)

                VStack(spacing: 4) {
                    Text("\(item.title.uppercased()) · \(shortEra(item))")
                        .font(MVFont.black(16))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(MV.C.ink)
                    Text(store.shieldDistanceLabel(for: item))
                        .font(MVFont.body(12, weight: 600))
                        .foregroundStyle(MV.C.ink.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(MV.C.dc.opacity(0.35))

                HStack(spacing: 0) {
                    Text(L10n.text("JÁ VI ISSO"))
                        .font(MVFont.bold(13))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .foregroundStyle(MV.C.card)
                        .background(MV.C.dc)
                        .contentShape(Rectangle())
                        .onTapGesture { store.shieldMarkSeen(item.id) }
                    Rectangle().fill(MV.C.ink).frame(width: MV.stroke)
                    Text(L10n.text("MOSTRAR MESMO ASSIM"))
                        .font(MVFont.bold(12))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .foregroundStyle(MV.C.ink)
                        .background(MV.C.card)
                        .contentShape(Rectangle())
                        .onTapGesture { store.revealShielded(reviewID: review.id) }
                }
            }
            .background(MV.C.card)
            .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
            .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .background(RoundedRectangle(cornerRadius: MV.R.xl).fill(MV.C.shadow).offset(x: MV.Shadow.s, y: MV.Shadow.s))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.format("Review escondida pelo escudo de spoiler, sobre %1$@", String(describing: item.title)))
        )
    }

    private func shortEra(_ item: Item) -> String {
        guard let idx = store.timelineIndex(for: item), let entries = store.timelines[item.uni] else { return "" }
        return entries[idx].era
    }
}
