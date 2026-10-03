import Foundation
import ImageIO

// Immutable CGImage is safe to share. Decode/downsample on the loader actor,
// never on the main actor, and keep only bounded thumbnails in memory.
final class CoverBitmap: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

private final class CoverRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Public CDN URLs are final. Never follow a redirect to a third-party host.
        completionHandler(nil)
    }
}

actor CatalogCoverLoader {
    static let shared = CatalogCoverLoader()
    private let session: URLSession
    private let cache = NSCache<NSString, CoverBitmap>()
    private struct Pending {
        let task: Task<CoverBitmap, Error>
        var consumers: Set<UUID>
    }
    private var pending: [String: Pending] = [:]

    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024,
                                             diskPath: "catalog-covers")
            configuration.requestCachePolicy = .useProtocolCachePolicy
            configuration.httpMaximumConnectionsPerHost = 4
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 25
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            self.session = URLSession(configuration: configuration, delegate: CoverRedirectPolicy(), delegateQueue: nil)
        }
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 120
    }

    func load(_ cover: CatalogCover, pixels: Int) async throws -> CoverBitmap {
        try Task.checkCancellation()
        let dimension = min(1024, max(64, ((pixels + 63) / 64) * 64))
        guard let url = cover.sizedURL(pixels: dimension) else { throw URLError(.badURL) }
        let key = "\(url.absoluteString)|\(dimension)"
        if let bitmap = cache.object(forKey: key as NSString) { return bitmap }
        let consumer = UUID()
        let task: Task<CoverBitmap, Error>
        if var existing = pending[key] {
            existing.consumers.insert(consumer)
            pending[key] = existing
            task = existing.task
        } else {
            task = Task { try await self.download(url, pixels: dimension) }
            pending[key] = Pending(task: task, consumers: [consumer])
        }
        return try await withTaskCancellationHandler {
            do {
                let bitmap = try await task.value
                try Task.checkCancellation()
                cache.setObject(bitmap, forKey: key as NSString, cost: bitmap.image.bytesPerRow * bitmap.image.height)
                release(key, consumer: consumer)
                return bitmap
            } catch {
                release(key, consumer: consumer)
                throw error
            }
        } onCancel: {
            Task { await self.release(key, consumer: consumer) }
        }
    }

    private func release(_ key: String, consumer: UUID) {
        guard var entry = pending[key], entry.consumers.remove(consumer) != nil else { return }
        if entry.consumers.isEmpty {
            entry.task.cancel()
            pending[key] = nil
        } else { pending[key] = entry }
    }

    private func download(_ url: URL, pixels: Int) async throws -> CoverBitmap {
        let (bytes, response) = try await session.bytes(from: url)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              ["image/jpeg", "image/png", "image/webp"].contains(response.mimeType ?? ""),
              response.expectedContentLength <= 8 * 1024 * 1024 else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 8 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        return CoverBitmap(image)
    }
}
