import SwiftUI

struct ReadingOrderView: View {
    let orderID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            if let order = store.readingOrders.first(where: { $0.id == orderID }), let uni = store.universe(order.uni) {
                let progress = store.orderProgress(order)
                VStack(alignment: .leading, spacing: 20) {
                    hero(order: order, uni: uni, progress: progress).padding(.horizontal, MV.pad)
                    steps(order: order, uni: uni).padding(.horizontal, MV.pad)
                }
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private func hero(order: ReadingOrder, uni: Universe, progress: (done: Int, total: Int)) -> some View {
        let voted = store.isOrderVoted(order.id)
        let following = store.isFollowingOrder(order.id)

        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.format("ORDEM DA COMUNIDADE · %1$@", String(describing: uni.name.uppercased()))).kicker(11).foregroundStyle(uni.inkColor.opacity(0.85))
            Text(order.title).font(MVFont.display(26, width: 118)).foregroundStyle(uni.inkColor)
            if let by = store.user(order.by) {
                Text(L10n.format("por %1$@ · %2$@ itens · %3$@ seguem", String(describing: by.handle), String(describing: order.steps.count), String(describing: Logic.fmt(Int((Double(order.votes) / 3).rounded())))))
                    .font(MVFont.body(12, weight: 600)).foregroundStyle(uni.inkColor.opacity(0.85))
            }

            VStack(alignment: .leading, spacing: 6) {
                ComicProgress(value: progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0, fill: uni.inkColor, height: 10)
                Text(L10n.format("%1$@ de %2$@", String(describing: progress.done), String(describing: progress.total))).font(MVFont.bold(12)).foregroundStyle(uni.inkColor)
            }

            HStack(spacing: 10) {
                Text("▲ \(Logic.fmt(store.orderVoteCount(order)))")
                    .font(MVFont.bold(14))
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .foregroundStyle(voted ? uni.inkColor : uni.color)
                    .background(voted ? uni.color : uni.inkColor)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .burstOnTap("BOOM!", color: MV.C.wow, when: !voted) {
                        store.voteOrder(order.id)
                    }

                Text(following ? L10n.text("✓ SEGUINDO") : L10n.text("SEGUIR ORDEM"))
                    .font(MVFont.bold(13))
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .foregroundStyle(following ? uni.inkColor : uni.color)
                    .background(following ? uni.color : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(uni.inkColor, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .contentShape(Rectangle())
                    .onTapGesture { store.toggleOrderFollow(order.id) }
            }
        }
        .padding(16)
        .background(uni.color)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xxl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xxl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .background(RoundedRectangle(cornerRadius: MV.R.xxl).fill(MV.C.shadow).offset(x: MV.Shadow.l, y: MV.Shadow.l))
    }

    @ViewBuilder
    private func steps(order: ReadingOrder, uni: Universe) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(order.steps.enumerated()), id: \.offset) { index, itemID in
                if let item = store.item(itemID) {
                    StepRow(number: index + 1, item: item, uni: uni)
                }
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let item: Item
    let uni: Universe
    @Environment(AppStore.self) private var store

    var body: some View {
        let seen = store.isSeen(item.id)
        HStack(spacing: 12) {
            Text("\(number)").font(MVFont.black(18)).foregroundStyle(MV.C.muted).frame(width: 26)

            Button { store.push(.item(item.id)) } label: {
                PosterView(item: item, universe: uni, width: 32, height: 48, titleSize: 7, showLabel: false)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(MVFont.bold(14))
                    .strikethrough(seen)
                    .foregroundStyle(MV.C.ink)
                Text("\(L10n.text(item.type)) · \(item.year.description) · ★ \(L10n.decimal(item.avg))")
                    .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
            }
            Spacer()

            ZStack {
                Circle().fill(seen ? uni.color : MV.C.card)
                if seen { Text("✓").font(MVFont.black(15)).foregroundStyle(uni.inkColor) }
            }
            .frame(width: 34, height: 34)
            .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .contentShape(Circle())
            .onTapGesture { store.toggleSeen(item.id) }
        }
        .padding(.vertical, 6)
    }
}
