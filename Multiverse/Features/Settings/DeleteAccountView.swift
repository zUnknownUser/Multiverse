import SwiftUI

struct DeleteAccountView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""
    @State private var exportURL: URL?
    @State private var isDeleting = false

    private let confirmationWord = "EXCLUIR"

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ZONA DE PERIGO").kicker(11).foregroundStyle(MV.C.paper.opacity(0.85))
                    Text("EXCLUIR SUA\nCONTA").font(MVFont.display(30, width: 118)).lineSpacing(-6).foregroundStyle(MV.C.paper)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ZStack(alignment: .leading) { MV.C.marvel; Halftone(color: MV.C.paper.opacity(0.16)) })
                .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
                .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .background(RoundedRectangle(cornerRadius: MV.R.xl).fill(MV.C.ink).offset(x: MV.Shadow.m, y: MV.Shadow.m))

                Text("Isso é permanente. Vai sumir tudo:").font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)

                VStack(alignment: .leading, spacing: 14) {
                    lossRow("\(store.diary.count) registros no diário")
                    lossRow("\(myReviewCount) reviews e seus comentários")
                    lossRow("\(store.lists.count) listas e \(store.readingOrders.count) ordens de leitura")
                    if let badge = topBadgeName { lossRow("Selo Lorista de \(badge)") }
                }
                .padding(16)
                .comicCard(shadow: MV.Shadow.s)

                VStack(alignment: .leading, spacing: 8) {
                    Text("DIGITE \(confirmationWord) PRA CONFIRMAR").kicker(11).foregroundStyle(MV.C.ink)
                    TextField("", text: $confirmationText)
                        .font(MVFont.black(18))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .frame(height: 54)
                        .background(MV.C.card)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
                }

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Text("Baixar meus dados antes (JSON)").font(MVFont.bold(13)).underline().foregroundStyle(MV.C.ink)
                    }
                }

                Spacer(minLength: 12)

                PrimaryAuthButton(title: "EXCLUIR PRA SEMPRE", isLoading: isDeleting, enabled: confirmationText == confirmationWord) {
                    Task {
                        isDeleting = true
                        try? await auth.deleteAccount()
                        store.isOnboarded = false
                        isDeleting = false
                    }
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
        .task { exportURL = makeExportFile() }
    }

    private var myReviewCount: Int { store.reviews.filter { $0.user == store.meID }.count }
    private var topBadgeName: String? { store.badgeNames[store.user(store.meID)?.badgeUniverse ?? ""] }

    private func lossRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text("✕").font(MVFont.black(13)).foregroundStyle(MV.C.ink)
            Text(text).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
        }
    }

    /// Exporta diário e reviews do usuário logado pra um JSON temporário (LGPD/portabilidade).
    private func makeExportFile() -> URL? {
        struct Export: Codable {
            let handle: String
            let diary: [DiaryEntry]
            let reviews: [Review]
        }
        let export = Export(handle: store.user(store.meID)?.handle ?? "", diary: store.diary, reviews: store.reviews.filter { $0.user == store.meID })
        guard let data = try? JSONEncoder().encode(export) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("multiverse-dados.json")
        try? data.write(to: url)
        return url
    }
}
