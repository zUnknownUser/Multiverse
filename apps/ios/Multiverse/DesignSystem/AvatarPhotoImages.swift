import SwiftUI

/// Memory-only and owned by one account session. Concurrent rows share one request.
@MainActor @Observable final class AvatarPhotoImages {
    private let fetch: @MainActor (String) async throws -> Data
    private let cache = NSCache<NSString, UIImage>()
    private var pending: [String: Task<UIImage?, Never>] = [:]
    private(set) var revision = 0
    init(fetch: @escaping @MainActor (String) async throws -> Data) {
        self.fetch = fetch
        cache.totalCostLimit = 12 * 1024 * 1024
        cache.countLimit = 80
    }
    func image(_ id: String) -> UIImage? { _ = revision; return cache.object(forKey: id as NSString) }
    func load(_ id: String) async {
        guard image(id) == nil else { return }
        let task: Task<UIImage?, Never>
        if let existing = pending[id] { task = existing }
        else {
            task = Task { [fetch] in
                guard let data = try? await fetch(id), !Task.isCancelled else { return nil }
                return UIImage(data: data)
            }
            pending[id] = task
        }
        if let image = await task.value {
            cache.setObject(image, forKey: id as NSString, cost: Int(image.size.width * image.size.height * 4))
            revision += 1
        }
        pending[id] = nil
    }
}
extension EnvironmentValues {
    @Entry var avatarPhotos: AvatarPhotoImages? = nil
}
struct AvatarPhotoOverlay: View {
    let id: String?
    @Environment(\.avatarPhotos) private var photos
    var body: some View {
        ZStack {
            Color.clear
            if let id, let image = photos?.image(id) { Image(uiImage: image).resizable().scaledToFill().clipShape(Circle()) }
        }.task(id: id) { if let id { await photos?.load(id) } }
    }
}
