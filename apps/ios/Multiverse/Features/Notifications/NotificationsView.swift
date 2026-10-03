import SwiftUI

struct NotificationsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("ATIVIDADE")).font(MVFont.display(28, width: 122))
                Text(L10n.text("O que o pessoal fez com o que você postou.")).font(MVFont.body(13, weight: 600)).foregroundStyle(MV.C.muted)
                if let notifications = store.notifications {
                    if let error = notifications.error {
                        AuthErrorBanner(message: error)
                        Button(L10n.text("TENTAR DE NOVO")) { Task { await notifications.refresh() } }
                    }
                    if notifications.busy { ProgressView() }
                    if notifications.entries.isEmpty && !notifications.busy && notifications.error == nil {
                        Text(L10n.text("Nenhuma atividade ainda. As novidades aparecerão aqui."))
                    }
                    if notifications.entries.contains(where: { $0.readAt == nil }) {
                        Button(L10n.text("MARCAR ESTAS COMO LIDAS")) { Task { _ = await notifications.markRead(notifications.entries.map(\.id)) } }.disabled(notifications.busy)
                    }
                    ForEach(notifications.entries) { entry in
                        Button { Task { await open(entry, in: notifications) } } label: {
                            HStack(alignment: .top, spacing: 12) {
                                if let user = notifications.users[entry.user] { AvatarView(user: user, size: 34) }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(notifications.users[entry.user]?.name ?? "").font(MVFont.bold(14))
                                    Text(entry.label).font(MVFont.body(13, weight: 500))
                                    Text(entry.createdAt, style: .relative).font(MVFont.body(11, weight: 500)).foregroundStyle(MV.C.muted)
                                }
                                Spacer()
                                if entry.readAt == nil { Circle().fill(MV.C.ink).frame(width: 8, height: 8).accessibilityLabel(L10n.text("Não lida")) }
                            }.foregroundStyle(MV.C.ink).padding(14).comicCard()
                        }.buttonStyle(.plain).disabled(notifications.busy)
                    }
                    if notifications.nextCursor != nil { Button(L10n.text("CARREGAR MAIS")) { Task { await notifications.refresh(more: true) } }.disabled(notifications.busy) }
                }
            }.padding(MV.pad)
        }.task { await store.notifications?.refresh() }
        .refreshable { await store.notifications?.refresh() }
    }
    private func open(_ entry: ActivityNotification, in notifications: NotificationStore) async {
        guard await notifications.markRead([entry.id]) else { return }
        switch entry.targetType {
        case "message": store.push(.conversation(entry.user))
        case "review": store.push(.review(entry.targetID))
        case "post": store.push(.post(entry.targetID))
        case "person": store.openUserProfile(entry.targetID)
        default: break
        }
    }
}
