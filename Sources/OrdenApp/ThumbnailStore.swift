import AppKit
import QuickLookThumbnailing

/// Miniaturas en caché para iconos de imagen/vídeo (QLThumbnailGenerator).
@MainActor
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 400
    }

    func thumbnail(for path: String, pointSize: CGFloat) async -> NSImage? {
        let pixel = max(24, Int(pointSize * (NSScreen.main?.backingScaleFactor ?? 2) * 1.5))
        let key = "\(path)#\(pixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: pixel, height: pixel),
            scale: 1,
            representationTypes: .thumbnail
        )

        let image: NSImage? = await withCheckedContinuation { cont in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                cont.resume(returning: rep?.nsImage)
            }
        }

        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }
}
