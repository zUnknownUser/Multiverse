import SwiftUI

struct PeopleStatusNotice: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AuthErrorBanner(message: message)
            PrimaryAuthButton(title: L10n.text("TENTAR DE NOVO")) {
                Task { await retry() }
            }
        }
    }
}
