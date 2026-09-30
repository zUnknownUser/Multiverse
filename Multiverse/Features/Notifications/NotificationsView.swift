import SwiftUI

struct NotificationsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ATIVIDADE").font(MVFont.display(28, width: 122)).foregroundStyle(MV.C.ink)
                    Text("O que o pessoal fez com o que você postou.")
                        .font(MVFont.body(13, weight: 600)).foregroundStyle(MV.C.muted)
                }

                VStack(spacing: 10) {
                    ForEach(StaticContent.notifications) { n in
                        NotificationRow(notification: n)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("TOP LORISTAS DA SEMANA").font(MVFont.section(17)).foregroundStyle(MV.C.ink)
                    VStack(spacing: 10) {
                        ForEach(StaticContent.leaderboard) { entry in
                            LeaderRow(entry: entry)
                        }
                    }
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
        .onAppear { store.unreadCount = 0 }
    }
}

private struct NotificationRow: View {
    let notification: StaticContent.NotificationItem
    @Environment(AppStore.self) private var store

    var body: some View {
        guard let user = store.user(notification.userID) else { return AnyView(EmptyView()) }
        let item = notification.itemID.flatMap { store.item($0) }

        return AnyView(
            HStack(alignment: .top, spacing: 10) {
                    AvatarView(user: user, size: 34)
                    VStack(alignment: .leading, spacing: 6) {
                        (Text(user.name).font(MVFont.bold(13))
                            + Text(" " + notification.text + " ").font(MVFont.body(13, weight: 500))
                            + Text(item?.title ?? "").font(MVFont.bold(13)))
                            .foregroundStyle(MV.C.ink)
                        if let quote = notification.quote {
                            Text(quote)
                                .font(MVFont.body(12, weight: 500))
                                .italic()
                                .foregroundStyle(MV.C.muted)
                                .padding(.leading, 10)
                                .overlay(alignment: .leading) { Rectangle().fill(MV.C.ink).frame(width: 3) }
                        }
                        Text(notification.when).font(MVFont.body(11, weight: 700)).foregroundStyle(MV.C.muted)
                    }
                    Spacer(minLength: 8)
                    if notification.isNewFollower {
                        let following = store.isFollowing(user.id)
                        Text(following ? "Seguindo" : "Seguir")
                            .font(MVFont.bold(11))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .foregroundStyle(following ? MV.C.ink : MV.C.paper)
                            .background(following ? Color.clear : MV.C.ink)
                            .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                            .clipShape(Capsule())
                            .burstOnTap("ZAP!", color: MV.C.dc, when: !following) {
                                store.toggleFollow(user.id)
                            }
                    } else if let item {
                        let uni = store.universe(of: item)
                        let p = Logic.posterColors(item: item, universe: uni)
                        ZStack { p.bg; Halftone() }
                            .frame(width: 36, height: 54)
                            .comicCard(bg: p.bg, radius: MV.R.sm, shadow: MV.Shadow.s)
                    }
            }
            .padding(10)
            .comicCard(shadow: MV.Shadow.s)
            .contentShape(Rectangle())
            .onTapGesture {
                if let rid = notification.reviewID { store.push(.review(rid)) }
                else { store.openUserProfile(user.id) }
            }
        )
    }
}

private struct LeaderRow: View {
    let entry: StaticContent.LeaderboardEntry
    @Environment(AppStore.self) private var store

    var body: some View {
        guard let user = store.user(entry.userID) else { return AnyView(EmptyView()) }
        let rank = (StaticContent.leaderboard.firstIndex { $0.userID == entry.userID } ?? 0) + 1
        let following = store.isFollowing(user.id)

        return AnyView(
            HStack(spacing: 10) {
                Text("\(rank)").font(MVFont.black(16)).foregroundStyle(MV.C.muted).frame(width: 22)
                AvatarView(user: user, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name).font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                    Text("\(entry.reviews) reviews · \(Logic.fmt(entry.likes)) curtidas")
                        .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                }
                Spacer()
                Text(following ? "Seguindo" : "Seguir")
                    .font(MVFont.bold(10))
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .foregroundStyle(following ? MV.C.ink : MV.C.paper)
                    .background(following ? Color.clear : MV.C.ink)
                    .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(Capsule())
                    .burstOnTap("ZAP!", color: MV.C.dc, when: !following) {
                        store.toggleFollow(user.id)
                    }
            }
            .padding(10)
            .comicCard(shadow: MV.Shadow.s)
            .contentShape(Rectangle())
            .onTapGesture { store.openUserProfile(user.id) }
        )
    }
}
