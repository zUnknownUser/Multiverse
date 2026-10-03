import SwiftUI

/// Discussão por trecho de um clube — recurso 1d.
struct ClubDiscussionView: View {
    let clubID: String
    let week: Int
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var segment = ""
    @State private var draft = ""

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            if let club = store.club(clubID), let clubWeek = club.weeks.first(where: { $0.week == week }), let item = store.item(clubWeek.itemID) {
                VStack(alignment: .leading, spacing: 14) {
                    header(club: club, item: item).padding(.horizontal, MV.pad)
                    segmentPicker(clubWeek: clubWeek).padding(.horizontal, MV.pad)
                    messagesList(clubWeek: clubWeek).padding(.horizontal, MV.pad)
                }
                .padding(.bottom, 90)
                .onAppear { if segment.isEmpty { segment = clubWeek.segments.first ?? "" } }
            }
        }
        .safeAreaInset(edge: .bottom) { replyBar }
    }

    @ViewBuilder
    private func header(club: Club, item: Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.format("%1$@ · SEMANA %2$@", String(describing: club.name.uppercased()), String(describing: week))).kicker(11).foregroundStyle(MV.C.muted)
            Text(item.title.uppercased()).font(MVFont.display(28, width: 120)).foregroundStyle(MV.C.ink)
        }
    }

    @ViewBuilder
    private func segmentPicker(clubWeek: ClubWeek) -> some View {
        HStack(spacing: 8) {
            ForEach(clubWeek.segments, id: \.self) { s in
                let selected = segment == s
                Text(s.uppercased())
                    .font(MVFont.bold(12))
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .foregroundStyle(selected ? MV.C.paper : MV.C.ink)
                    .background(selected ? MV.C.ink : MV.C.card)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .contentShape(Rectangle())
                    .onTapGesture { segment = s }
            }
        }
    }

    @ViewBuilder
    private func messagesList(clubWeek: ClubWeek) -> some View {
        let messages = store.clubMessagesFor(clubID: clubID, week: week, segment: segment)
        let myUnits = store.clubUnitsCompleted(clubID: clubID, userID: store.meID)
        let hiddenCount = messages.filter { store.isClubMessageHidden($0, clubID: clubID) }.count

        VStack(spacing: 12) {
            ForEach(messages) { message in
                if store.isClubMessageHidden(message, clubID: clubID) {
                    EmptyView()
                } else {
                    ClubMessageBubble(message: message)
                }
            }
            if hiddenCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("◆ ESCUDO"))
                        .font(MVFont.black(10)).tracking(0.4)
                        .foregroundStyle(MV.C.card)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(MV.C.dc)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.xs).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.xs))
                    Text(L10n.format("club.hiddenMessages", hiddenCount, clubWeek.unitLabel.lowercased(), String(myUnits)))
                        .font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                    Button(L10n.format("Já li o %1$@ %2$@", String(describing: clubWeek.unitLabel.lowercased()), String(describing: myUnits + 1))) {
                        store.setMyClubUnits(clubID: clubID, units: myUnits + 1)
                    }
                    .font(MVFont.bold(13)).underline().foregroundStyle(MV.C.ink)
                    .buttonStyle(.plain)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MV.C.dc.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
                .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .background(RoundedRectangle(cornerRadius: MV.R.xl).fill(MV.C.shadow).offset(x: MV.Shadow.s, y: MV.Shadow.s))
            }
        }
    }

    private var replyBar: some View {
        HStack(spacing: 8) {
            TextField(L10n.format("Comentar sobre %1$@…", String(describing: segment)), text: $draft)
                .font(MVFont.body(14, weight: 500))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(MV.C.card)
                .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(Capsule())
                .onSubmit(send)
            Text(L10n.text("ENVIAR"))
                .font(MVFont.bold(12))
                .padding(.horizontal, 16).frame(height: 44)
                .foregroundStyle(MV.C.paper)
                .background(MV.C.ink)
                .clipShape(Capsule())
                .contentShape(Rectangle())
                .onTapGesture(perform: send)
        }
        .padding(.horizontal, MV.pad)
        .padding(.vertical, 10)
        .background(MV.C.paper)
        .overlay(alignment: .top) { Rectangle().fill(MV.C.ink).frame(height: MV.stroke) }
    }

    private func send() {
        store.postClubMessage(clubID: clubID, week: week, segment: segment, text: draft)
        draft = ""
    }
}

private struct ClubMessageBubble: View {
    let message: ClubMessage
    @Environment(AppStore.self) private var store

    var body: some View {
        guard let user = store.user(message.userID) else { return AnyView(EmptyView()) }
        let isMe = user.id == store.meID
        let hearted = store.isClubMessageHearted(message.id)

        return AnyView(
            HStack {
                if isMe { Spacer(minLength: 40) }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        if !isMe { AvatarView(user: user, size: 30) }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(isMe ? L10n.text("Você") : user.name).font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                                Spacer()
                                Text(message.when).font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                            }
                            Text(message.text).font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)
                        }
                        if isMe { AvatarView(user: user, size: 30) }
                    }
                    .padding(12)
                    .background(isMe ? MV.C.accent : MV.C.card)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.lg).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.lg))

                    if message.hearts > 0 || message.pows > 0 || !isMe {
                        HStack(spacing: 6) {
                            reactionPill(text: "♥ \(message.hearts)", active: hearted, color: MV.C.marvel) {
                                store.toggleClubMessageHeart(message.id)
                            }
                            reactionPill(text: "POW! \(message.pows)", active: store.powedClubMessages.contains(message.id), color: MV.C.accent) {
                                store.powClubMessage(message.id)
                            }
                        }
                    }
                }
                if !isMe { Spacer(minLength: 40) }
            }
        )
    }

    private func reactionPill(text: String, active: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Text(text)
            .font(MVFont.bold(11))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(active ? MV.C.card : MV.C.ink)
            .background(active ? color : MV.C.card)
            .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(Capsule())
            .burstOnTap(color == MV.C.marvel ? "POW!" : "BAM!", color: color, when: !active) { action() }
    }
}
