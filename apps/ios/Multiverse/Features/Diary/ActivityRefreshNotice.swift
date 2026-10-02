import SwiftUI

/// Reuses the existing error and button styles without replacing saved content.
struct ActivityRefreshNotice: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let error = store.activityRefreshError {
            VStack(alignment: .leading, spacing: 10) {
                AuthErrorBanner(message: L10n.text("Não foi possível atualizar. Seus últimos dados continuam aqui.") + "\n" + error)
                PrimaryAuthButton(title: L10n.text("TENTAR DE NOVO")) {
                    Task { await store.refreshActivity() }
                }
                .disabled(store.isRefreshingActivity)
            }
        }
    }
}
