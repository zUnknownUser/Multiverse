import SwiftUI

struct CatalogPageControls<Value: Sendable>: View {
    let state: CatalogPageState<Value>
    let load: (Bool) async -> Void
    var body: some View {
        if state.loading { ProgressView().frame(maxWidth: .infinity) }
        if let error = state.error {
            AuthErrorBanner(message: error)
            Button(L10n.text("TENTAR DE NOVO")) { Task { await load(state.loaded && state.nextCursor != nil) } }.disabled(state.loading)
        } else if state.nextCursor != nil {
            PrimaryAuthButton(title: L10n.text("CARREGAR MAIS")) { Task { await load(true) } }.disabled(state.loading)
        }
    }
}

/// Failed reads remain retryable; a confirmed missing ID may be shown as unavailable.
private struct CatalogReferenceTaskKey: Hashable {
    let ids: [String]
    let generation: Int
}

struct CatalogReferenceStatus: View {
    let ids: [String]
    @Environment(AppStore.self) private var store
    var body: some View {
        Group {
            if store.catalogStore.paginated {
                if ids.contains(where: { store.catalogStore.resolvingIDs.contains($0) }) { ProgressView() }
                if let error = ids.compactMap({ store.catalogStore.itemErrors[$0] }).first {
                    AuthErrorBanner(message: error)
                    Button(L10n.text("TENTAR DE NOVO")) { Task { await store.catalogStore.resolve(ids) } }
                }
            }
        }.task(id: CatalogReferenceTaskKey(ids: ids, generation: store.catalogStore.generation)) {
            await store.catalogStore.resolve(ids)
        }
    }
}
