import SwiftUI

extension ProfileAvatar {
    var title: String {
        switch self {
        case .vigilant: L10n.text("Vigilante")
        case .cosmic: L10n.text("Exploradora cósmica")
        case .robot: L10n.text("Robô heroico")
        }
    }
    @MainActor var image: UIImage? { Self.images[rawValue] }
    // Crop the supplied sprite sheet once, never decode it for every feed row.
    @MainActor private static let images: [String: UIImage] = {
        guard let source = UIImage(named: "AvatarCollection")?.cgImage else { return [:] }
        let scale = CGFloat(source.width) / 1408
        return Dictionary(uniqueKeysWithValues: zip(allCases, [CGFloat(0), 448, 898]).compactMap { avatar, x in
            let rect = CGRect(x: x * scale, y: 125 * scale, width: 500 * scale, height: 500 * scale)
            guard let crop = source.cropping(to: rect) else { return nil }
            return (avatar.rawValue, UIImage(cgImage: crop))
        })
    }()
}

struct ProfileAvatarFace: View {
    let name: String
    let color: String
    let avatarID: String?
    let size: CGFloat
    var body: some View {
        ZStack {
            Color(hex: color)
            if let avatarID, let avatar = ProfileAvatar(rawValue: avatarID), let image = avatar.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(Logic.initials(name)).font(MVFont.black(size * 0.36))
                    .foregroundStyle(Logic.inkOn(hex: color))
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .accessibilityHidden(true)
    }
}
