import UIKit
import ImageIO

struct PreparedPhoto: Identifiable, Sendable { let id: String; let data: Data; let preview: UIImage }
/// Serial background processing keeps decoding/re-encoding off the UI actor.
actor PhotoProcessor {
    static let shared = PhotoProcessor()
    func prepare(_ data: Data) throws -> PreparedPhoto {
        try Task.checkCancellation()
        let photo = try PhotoPreparation.prepare(data)
        try Task.checkCancellation()
        return photo
    }
}
enum PhotoPreparation {
    static func prepare(_ data: Data) throws -> PreparedPhoto {
        guard data.count <= 30_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw CommunityError.invalidImage }
        let picture = UIImage(cgImage: thumbnail)
        guard let jpeg = picture.jpegData(compressionQuality: 0.8), jpeg.count <= 2_000_000 else { throw CommunityError.invalidImage }
        return PreparedPhoto(id: UUID().uuidString.lowercased(), data: jpeg, preview: picture)
    }
}
