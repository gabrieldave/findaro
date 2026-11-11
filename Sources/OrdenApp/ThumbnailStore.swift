import AppKit
import AVFoundation
import QuickLookThumbnailing
import OrdenCore

/// Miniaturas en caché. Vídeo usa AVFoundation (evita el icono fantasma de VLC).
@MainActor
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private let cache = NSCache<NSString, NSImage>()

    private static let versionKey = "ordena.thumbnailCacheVersion"

    private init() {
        cache.countLimit = 400
    }

    /// Limpia miniaturas en memoria.
    func clearAll() {
        cache.removeAllObjects()
    }

    /// Tras instalar otra build, vacía caché sola (no hace falta venir al chat).
    static func clearIfAppUpdated() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let stamp = "\(version).\(build)"
        let previous = UserDefaults.standard.string(forKey: versionKey)
        guard previous != stamp else { return }
        UserDefaults.standard.set(stamp, forKey: versionKey)
        shared.clearAll()
    }

    func thumbnail(for path: String, pointSize: CGFloat) async -> NSImage? {
        // Max Retina de todos los displays (evita thumbs borrosos en monitor externo).
        let scale = NSScreen.screens.map(\.backingScaleFactor).max()
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        let pixel = max(24, Int(pointSize * scale * 1.5))
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let attrs = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        let sizeStamp = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtimeStamp = Int((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        let key = "\(path)#\(pixel)#\(sizeStamp)#\(mtimeStamp)" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let category = FileCategory.classify(fileName: name, isDirectory: false)

        let image: NSImage?
        if category == .video {
            image = await videoFrame(url: url, pixel: pixel)
        } else {
            image = await quickLookThumb(url: url, pixel: pixel)
                ?? (category == .image ? NSImage(contentsOf: url) : nil)
        }

        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    private func quickLookThumb(url: URL, pixel: Int) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: pixel, height: pixel),
            scale: 1,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { cont in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                cont.resume(returning: rep?.nsImage)
            }
        }
    }

    private func videoFrame(url: URL, pixel: Int) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: pixel * 2, height: pixel * 2)
        let primary = CMTime(seconds: 0.5, preferredTimescale: 600)
        if let image = await generateFrame(gen, at: primary) {
            return image
        }
        return await generateFrame(gen, at: .zero)
    }

    private func generateFrame(_ gen: AVAssetImageGenerator, at time: CMTime) async -> NSImage? {
        await withCheckedContinuation { cont in
            gen.generateCGImageAsynchronously(for: time) { cg, _, _ in
                guard let cg else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
            }
        }
    }
}
