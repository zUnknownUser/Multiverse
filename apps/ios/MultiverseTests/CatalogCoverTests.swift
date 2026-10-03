import Foundation
import Testing
import UIKit
@testable import Multiverse

private final class CoverHTTPFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var body = Data()
    private var status = 200
    private var mime = "image/png"
    func reset(_ data: Data, status: Int = 200, mime: String = "image/png") {
        lock.lock(); defer { lock.unlock() }
        body = data; self.status = status; self.mime = mime; count = 0
    }
    func response() -> (Data, Int, String) {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return (body, status, mime)
    }
    var requests: Int { lock.lock(); defer { lock.unlock() }; return count }
}
private final class CoverURLProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = CoverHTTPFixture()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (data, status, mime) = Self.fixture.response()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": mime, "Content-Length": String(data.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct CatalogCoverTests {
    private let cover = CatalogCover(provider: "tmdb", url: "https://image.tmdb.org/t/p/w500/abc123.jpg",
                                     sourceURL: "https://www.themoviedb.org/movie/299534")
    @Test func providerValidationAndSizeSelection() {
        #expect(cover.sizedURL(pixels: 180)?.path == "/t/p/w185/abc123.jpg")
        #expect(cover.sizedURL(pixels: 300)?.path == "/t/p/w342/abc123.jpg")
        #expect(cover.sizedURL(pixels: 800)?.path == "/t/p/w500/abc123.jpg")
        for url in ["http://image.tmdb.org/t/p/w500/a.jpg", "https://image.tmdb.org.evil.test/t/p/w500/a.jpg",
                    "https://image.tmdb.org/t/p/w500/a.jpg?token=secret", "https://image.tmdb.org/t/p/w500/../a.jpg"] {
            #expect(CatalogCover(provider: "tmdb", url: url, sourceURL: "").imageURL == nil)
        }
        #expect(CatalogCover(provider: "metron", url: cover.url, sourceURL: "").imageURL == nil)
    }
    @Test @MainActor func sharesDownloadsDownsamplesAndCaches() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 1500))
        let data = renderer.pngData { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 1500)) }
        CoverURLProtocol.fixture.reset(data)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CoverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = CatalogCoverLoader(session: session)
        async let first = loader.load(cover, pixels: 180)
        async let second = loader.load(cover, pixels: 180)
        let results = try await (first, second)
        #expect(results.0.image.height <= 192)
        #expect(results.0 === results.1)
        let cached = try await loader.load(cover, pixels: 180)
        #expect(cached === results.0)
        #expect(CoverURLProtocol.fixture.requests == 1)
    }
    @Test func invalidResponsesAndCancellationNeverProduceArtwork() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CoverURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let loader = CatalogCoverLoader(session: session)
        for status in [404, 503, 200] {
            CoverURLProtocol.fixture.reset(Data("not an image".utf8), status: status)
            await #expect(throws: (any Error).self) { try await loader.load(cover, pixels: 200) }
        }
        CoverURLProtocol.fixture.reset(Data(), mime: "text/html")
        await #expect(throws: (any Error).self) { try await loader.load(cover, pixels: 200) }
        let task = Task { try Task.checkCancellation(); return try await loader.load(cover, pixels: 200) }
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
    }
    @Test func oldItemsRemainDecodableAndCoverRoundTrips() throws {
        var item = SampleData.load().items[0]
        #expect(item.cover == nil)
        item.cover = cover
        #expect(try JSONDecoder().decode(Item.self, from: JSONEncoder().encode(item)).cover == cover)
    }
}
