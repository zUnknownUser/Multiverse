import SwiftUI

/// "Clube da Cidadela" — recurso 1c.
struct ClubDetailView: View {
    let clubID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            if let club = store.club(clubID), let uni = store.universe(club.uni), let week = store.currentClubWeek(club) {
                VStack(alignment: .leading, spacing: 18) {
                    hero(club: club, uni: uni, week: week).padding(.horizontal, MV.pad)
                    if let item = store.item(week.itemID) {
                        thisWeekCard(item: item, uni: uni, week: week).padding(.horizontal, MV.pad)
                    }
                    discussionButton(club: club, uni: uni, week: week).padding(.horizontal, MV.pad)
                    membersSection(club: club, week: week).padding(.horizontal, MV.pad)
                    actionsRow(club: club).padding(.horizontal, MV.pad)
                }
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private func hero(club: Club, uni: Universe, week: ClubWeek) -> some View {
        ZStack(alignment: .topLeading) {
            uni.color
            Halftone(color: uni.inkColor.opacity(0.18))
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.format("CLUBE · %1$@", String(describing: uni.name.uppercased()))).kicker(11).foregroundStyle(uni.inkColor.opacity(0.85))
                Text(club.name.uppercased()).font(MVFont.display(34, width: 122)).foregroundStyle(uni.inkColor)
                if let order = store.readingOrders.first(where: { $0.id == club.orderID }) {
                    Text(L10n.format("%1$@ membros · seguindo \"%2$@\" · 1 item por semana", String(describing: club.memberIDs.count), String(describing: order.title)))
                        .font(MVFont.body(12, weight: 600)).foregroundStyle(uni.inkColor.opacity(0.85))
                }

                HStack(spacing: 6) {
                    ForEach(club.weeks, id: \.week) { w in
                        weekPill(w: w, current: club.currentWeek, uni: uni)
                    }
                }
                .padding(.top, 4)

                Text(L10n.format("SEMANA %1$@ DE %2$@ · TERMINA DOMINGO", String(describing: club.currentWeek), String(describing: club.weeks.count)))
                    .font(MVFont.bold(11)).foregroundStyle(uni.inkColor.opacity(0.85))
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xxl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xxl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .background(RoundedRectangle(cornerRadius: MV.R.xxl).fill(MV.C.shadow).offset(x: MV.Shadow.l, y: MV.Shadow.l))
    }

    @ViewBuilder
    private func weekPill(w: ClubWeek, current: Int, uni: Universe) -> some View {
        let done = w.week < current
        let isCurrent = w.week == current
        Group {
            if done { Text("✓") } else { Text("\(w.week)") }
        }
        .font(MVFont.black(14))
        .frame(width: 38, height: 38)
        .foregroundStyle(done || isCurrent ? uni.inkColor : uni.color)
        .background(done ? MV.C.ink : (isCurrent ? MV.C.card : MV.C.ink.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.sm))
    }

    @ViewBuilder
    private func thisWeekCard(item: Item, uni: Universe, week: ClubWeek) -> some View {
        let units = store.clubUnitsCompleted(clubID: clubID, userID: store.meID)
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("DESTA SEMANA")).kicker(11).foregroundStyle(MV.C.muted)
            HStack(alignment: .top, spacing: 12) {
                Button { store.push(.item(item.id)) } label: {
                    PosterView(item: item, universe: uni, width: 66, height: 99, titleSize: 10)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title.uppercased()).font(MVFont.black(16)).foregroundStyle(MV.C.ink)
                    Text(week.paceLabel).font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.muted)
                    HStack(spacing: 8) {
                        ComicProgress(value: week.totalUnits > 0 ? Double(units) / Double(week.totalUnits) : 0, fill: uni.color, height: 14)
                        Text("\(units)/\(week.totalUnits)").font(MVFont.bold(12)).foregroundStyle(MV.C.ink)
                    }
                }
            }
        }
        .padding(14)
        .comicCard(shadow: MV.Shadow.s)
    }

    @ViewBuilder
    private func discussionButton(club: Club, uni: Universe, week: ClubWeek) -> some View {
        let count = store.clubMessageCount(clubID: club.id, week: club.currentWeek)
        Button { store.push(.clubDiscussion(clubID: club.id, week: club.currentWeek)) } label: {
            HStack {
                Text(L10n.format("DISCUSSÃO DA SEMANA · %1$@ MSGS", String(describing: count))).font(MVFont.bold(14)).foregroundStyle(MV.C.paper)
                Spacer()
                Text("→").font(MVFont.black(16)).foregroundStyle(MV.C.paper)
            }
            .padding(16)
            .background(MV.C.ink)
            .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
            .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .background(RoundedRectangle(cornerRadius: MV.R.xl).fill(uni.color).offset(x: MV.Shadow.s, y: MV.Shadow.s))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func membersSection(club: Club, week: ClubWeek) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.format("QUEM ESTÁ EM QUAL %1$@", String(describing: week.unitLabel.uppercased()))).kicker(11).foregroundStyle(MV.C.muted)
            VStack(spacing: 10) {
                ForEach(club.memberIDs, id: \.self) { userID in
                    if let user = store.user(userID) {
                        memberRow(user: user, club: club, week: week)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func memberRow(user: User, club: Club, week: ClubWeek) -> some View {
        let units = store.clubUnitsCompleted(clubID: club.id, userID: user.id)
        let label = store.clubMemberProgressLabel(clubID: club.id, userID: user.id, week: week)
        HStack(spacing: 10) {
            AvatarView(user: user, size: 30)
            Text(user.id == store.meID ? L10n.text("Você") : user.name.components(separatedBy: " ").first ?? user.name)
                .font(MVFont.bold(13)).foregroundStyle(MV.C.ink).frame(width: 60, alignment: .leading)
            ComicProgress(value: week.totalUnits > 0 ? Double(units) / Double(week.totalUnits) : 0, fill: MV.C.accent, height: 12)
            Text(label).font(MVFont.bold(12)).foregroundStyle(MV.C.muted).frame(width: 70, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func actionsRow(club: Club) -> some View {
        HStack(spacing: 10) {
            Text(L10n.text("CUTUCAR\nATRASADOS"))
                .font(MVFont.bold(13)).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading).frame(height: 54)
                .foregroundStyle(MV.C.ink)
                .padding(.horizontal, 14)
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .contentShape(Rectangle())
                .onTapGesture { store.pokeLaggingMembers() }
            Text(L10n.text("CONVIDAR"))
                .font(MVFont.bold(13))
                .frame(maxWidth: .infinity).frame(height: 54)
                .foregroundStyle(MV.C.ink)
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .contentShape(Rectangle())
                .onTapGesture { store.inviteToClub() }
        }
    }
}
