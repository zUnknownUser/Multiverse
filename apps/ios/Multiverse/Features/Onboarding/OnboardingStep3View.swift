import SwiftUI

struct OnboardingStep3View: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let people = store.onboardingPeopleSorted()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("3 de 3")).kicker(11).foregroundStyle(MV.C.muted)
                    Text(L10n.format("onboarding.followMinimum", store.minimumOnboardingFollows))
                        .font(MVFont.display(26, width: 118))
                        .lineSpacing(-3)
                        .foregroundStyle(MV.C.ink)
                    Text(L10n.text("Seu feed é feito das reviews, votos e listas deles."))
                        .font(MVFont.body(14)).foregroundStyle(MV.C.muted)
                }

                Button {
                    store.followAll(people.map(\.id))
                } label: {
                    Text(L10n.text("Seguir todos")).font(MVFont.bold(12)).underline().foregroundStyle(MV.C.ink)
                }
                .buttonStyle(.plain)

                VStack(spacing: 10) {
                    ForEach(people) { user in
                        OnboardingPersonRow(user: user)
                    }
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.top, 18)
        }
        .scrollIndicators(.hidden)
    }
}

private struct OnboardingPersonRow: View {
    let user: User
    @Environment(AppStore.self) private var store

    var body: some View {
        let following = store.isFollowing(user.id)
        HStack(spacing: 10) {
            AvatarView(user: user, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.name).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                    if let uni = store.universe(user.badgeUniverse), let badge = store.badgeNames[user.badgeUniverse] {
                        BadgeChip(label: badge, universe: uni)
                    }
                }
                Text(store.usesAccountAPI ? user.bio : L10n.format("%1$@%% afinidade · %2$@", String(describing: Logic.compat(user.id)), String(describing: user.bio)))
                    .font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                    .lineLimit(1)
            }
            Spacer()
            Text(following ? L10n.text("Seguindo") : L10n.text("Seguir"))
                .font(MVFont.bold(12))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(following ? MV.C.ink : MV.C.paper)
                .background(Capsule().fill(following ? Color.clear : MV.C.ink))
                .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .burstOnTap("ZAP!", color: MV.C.dc, when: !following) {
                    store.toggleFollow(user.id, silent: true)
                }
        }
        .padding(10)
        .comicCard(shadow: MV.Shadow.s)
    }
}
