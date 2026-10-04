import Foundation
import Testing
import UIKit
@testable import Multiverse

@Suite @MainActor struct ProfileAvatarTests {
    @Test func shippedCollectionHasThreeDistinctCachedImages() throws {
        #expect(ProfileAvatar.allCases.count == 3)
        let images = try ProfileAvatar.allCases.map { try #require($0.image) }
        #expect(images.allSatisfy { $0.size.width > 0 && $0.size.width == $0.size.height })
        #expect(Set(images.compactMap { $0.pngData() }).count == 3)
        #expect(ProfileAvatar.vigilant.image === ProfileAvatar.vigilant.image)
    }
    @Test func legacyProfilesAndUnknownAvatarsRemainReadable() throws {
        let json = ##"{"id":"u","name":"User","handle":"@user","avatarColor":"#F4A814","bio":"","followers":0,"badgeUniverse":""}"##
        let old = try JSONDecoder().decode(User.self, from: Data(json.utf8))
        #expect(old.avatarID == nil)
        var newer = old; newer.avatarID = "future-avatar"
        let decoded = try JSONDecoder().decode(User.self, from: JSONEncoder().encode(newer))
        #expect(decoded.avatarID == "future-avatar")
        #expect(ProfileAvatar(rawValue: decoded.avatarID!) == nil)
    }
}
