import Foundation
import UIKit
import SwiftUI
import Testing
@testable import Multiverse

@Suite(.serialized) @MainActor struct ProfilePhotoTests {
    @Test func emptyPhotoOverlayStartsLoadingWhenMounted() async throws {
        let data = ProfileAvatar.robot.image!.jpegData(compressionQuality: 0.8)!
        let photos = AvatarPhotoImages { _ in data }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: AvatarPhotoOverlay(id: "photo").frame(width: 64, height: 64).environment(\.avatarPhotos, photos))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<50 where photos.image("photo") == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(photos.image("photo") != nil)
    }
    @Test func repeatedRowsShareOnePhotoRequestAndAccountCachesAreSeparate() async throws {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }.pngData()!
        var requests = 0
        let images = AvatarPhotoImages { _ in requests += 1; try await Task.sleep(for: .milliseconds(20)); return png }
        async let first: Void = images.load("photo")
        async let second: Void = images.load("photo")
        _ = await (first, second)
        #expect(requests == 1 && images.image("photo") != nil)
        await images.load("photo")
        #expect(requests == 1)
        let other = AvatarPhotoImages { _ in throw AuthError.networkUnavailable }
        #expect(other.image("photo") == nil)
        await other.load("photo")
        #expect(other.image("photo") == nil && images.image("photo") != nil)
    }
}
