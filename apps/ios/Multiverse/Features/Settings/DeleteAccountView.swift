import SwiftUI

struct DeleteAccountView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var isDeleting = false

    private let confirmationWord = L10n.text("EXCLUIR")

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("ZONA DE PERIGO")).kicker(11).foregroundStyle(MV.C.paper.opacity(0.85))
                    Text(L10n.text("EXCLUIR SUA\nCONTA")).font(MVFont.display(30, width: 118)).lineSpacing(-6).foregroundStyle(MV.C.paper)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ZStack(alignment: .leading) { MV.C.marvel; Halftone(color: MV.C.paper.opacity(0.16)) })
                .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
                .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .background(RoundedRectangle(cornerRadius: MV.R.xl).fill(MV.C.shadow).offset(x: MV.Shadow.m, y: MV.Shadow.m))

                Text(L10n.text("Isso é permanente. Vai sumir tudo:")).font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)

                VStack(alignment: .leading, spacing: 14) {
                    lossRow(L10n.format("%1$@ registros no diário", String(describing: store.diaryCount)))
                    lossRow(L10n.format("%1$@ reviews e seus comentários", String(describing: myReviewCount)))
                    lossRow(L10n.format("%1$@ listas e %2$@ ordens de leitura", String(describing: store.lists.count), String(describing: store.readingOrders.count)))
                    if let badge = topBadgeName { lossRow(L10n.format("Selo Lorista de %1$@", String(describing: badge))) }
                }
                .padding(16)
                .comicCard(shadow: MV.Shadow.s)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.format("DIGITE %1$@ PRA CONFIRMAR", String(describing: confirmationWord))).kicker(11).foregroundStyle(MV.C.ink)
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

                if let exportError {
                    AuthErrorBanner(message: exportError)
                    Button(L10n.text("TENTAR DE NOVO")) { Task { await prepareExport() } }
                }
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Text(L10n.text("Baixar meus dados antes (JSON)")).font(MVFont.bold(13)).underline().foregroundStyle(MV.C.ink)
                    }
                }

                Spacer(minLength: 12)

                PrimaryAuthButton(title: L10n.text("EXCLUIR PRA SEMPRE"), isLoading: isDeleting, enabled: confirmationText == confirmationWord) {
                    Task {
                        isDeleting = true
                        defer { isDeleting = false }
                        do {
                            try await auth.deleteAccount()
                            store.isOnboarded = false
                        } catch { auth.errorMessage = error.localizedDescription }
                    }
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
        .task { await prepareExport() }
    }

    private var myReviewCount: Int { store.diaryReviewCount }
    private var topBadgeName: String? { store.badgeNames[store.user(store.meID)?.badgeUniverse ?? ""] }

    private func lossRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text("✕").font(MVFont.black(13)).foregroundStyle(MV.C.ink)
            Text(text).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
        }
    }

    /// Exporta diário e reviews do usuário logado pra um JSON temporário (LGPD/portabilidade).
    private func prepareExport() async {
        struct Export: Codable {
            let handle: String
            let diary: [DiaryEntry]
            let reviews: [Review]
        }
        do {
            exportError = nil
            let snapshot = try await store.exportActivity()
            let export = Export(handle: store.user(store.meID)?.handle ?? "", diary: snapshot?.entries ?? store.diary,
                                reviews: snapshot?.reviews.map(\.display) ?? store.reviews.filter { $0.user == store.meID })
            let data = try JSONEncoder().encode(export)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("multiverse-dados-\(UUID().uuidString).json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = url
        } catch { exportError = error.localizedDescription }
    }
}
