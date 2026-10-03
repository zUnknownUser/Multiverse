import SwiftUI

/// Overlay only: never participates in the placeholder's layout or hit testing.
struct CatalogCoverOverlay: View {
    let cover: CatalogCover?
    let width: CGFloat
    let height: CGFloat
    @Environment(\.displayScale) private var displayScale
    @State private var bitmap: CoverBitmap?
    @State private var loadedCover: CatalogCover?

    var body: some View {
        Group {
            if let bitmap, loadedCover == cover {
                Image(decorative: bitmap.image, scale: 1)
                    .resizable().scaledToFill()
                    .frame(width: width, height: height).clipped()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: "\(cover?.url ?? "")|\(pixels)") {
            bitmap = nil
            loadedCover = nil
            guard let cover else { return }
            do {
                let loaded = try await CatalogCoverLoader.shared.load(cover, pixels: pixels)
                try Task.checkCancellation()
                bitmap = loaded
                loadedCover = cover
            } catch { /* The existing artwork remains visible, including offline. */ }
        }
    }
    private var pixels: Int { Int(min(1024, max(64, max(width, height) * displayScale))) }
}
