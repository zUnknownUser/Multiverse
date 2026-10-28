import SwiftUI

/// Scoped reviews are fetched independently of the currently open diary page/filter.
struct OwnReviews: View {
    var itemID: String? = nil
    var universeID: String? = nil
    var limit = 5
    @Environment(AppStore.self) private var store
    @State private var reviews: [Review] = []
    @State private var error: String?
    @State private var loading = true
    @State private var generation = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if loading { ProgressView() }
            else if let error {
                AuthErrorBanner(message: error)
                Button(L10n.text("TENTAR DE NOVO")) { Task { await load() } }
            } else if reviews.isEmpty, itemID != nil {
                Text(L10n.text("Você ainda não registrou uma nota ou review para esta obra."))
                    .font(MVFont.body(13)).foregroundStyle(MV.C.muted)
                    .frame(maxWidth: .infinity).padding(24).comicCard(shadow: 0, dashed: true)
            } else {
                ForEach(Array(reviews.prefix(limit))) { review in FeedReviewCard(review: review) }
            }
        }
        .task(id: "\(itemID ?? "")|\(universeID ?? "")|\(store.diaryStore.revision)|\(store.isMutatingActivity)") {
            await load()
        }
    }

    private func load() async {
        let request = UUID()
        generation = request
        guard !store.isMutatingActivity else { return }
        loading = true
        error = nil
        defer { if request == generation { loading = false } }
        do {
            let result = try await store.diaryStore.fetchReviews(itemID: itemID, universeID: universeID)
            guard request == generation else { return }
            reviews = result
        } catch is CancellationError { return }
        catch { if request == generation { self.error = error.localizedDescription } }
    }
}
