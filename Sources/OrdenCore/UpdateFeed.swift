import Foundation

/// Selección de canal de actualización según identidad del bundle instalado.
public enum UpdateFeed {
    public static let findaroBundleID = "app.findaro.files"
    public static let ordenaBundleID = "app.ordena.files"
    public static let allowedHosts: Set<String> = ["ordena.iareal.net"]

    public struct PublicFeed: Equatable, Sendable, Codable {
        public var version: String
        public var tag: String?
        public var dmg_url: String
        public var notes_url: String
        public var sha256: String?
        public var findaro_dmg_url: String?
        public var findaro_sha256: String?

        public init(
            version: String,
            tag: String? = nil,
            dmg_url: String,
            notes_url: String,
            sha256: String? = nil,
            findaro_dmg_url: String? = nil,
            findaro_sha256: String? = nil
        ) {
            self.version = version
            self.tag = tag
            self.dmg_url = dmg_url
            self.notes_url = notes_url
            self.sha256 = sha256
            self.findaro_dmg_url = findaro_dmg_url
            self.findaro_sha256 = findaro_sha256
        }
    }

    public struct ChannelRelease: Equatable, Sendable {
        public var version: String
        public var tag: String
        public var dmgURL: URL
        public var notesURL: URL
        public var sha256: String
        public var expectedBundleID: String

        public init(
            version: String,
            tag: String,
            dmgURL: URL,
            notesURL: URL,
            sha256: String,
            expectedBundleID: String
        ) {
            self.version = version
            self.tag = tag
            self.dmgURL = dmgURL
            self.notesURL = notesURL
            self.sha256 = sha256
            self.expectedBundleID = expectedBundleID
        }
    }

    public enum FeedError: Error, Equatable, LocalizedError {
        case unknownBundleID(String)
        case missingChannelURL
        case missingSHA256
        case invalidURL
        case disallowedHost(String)
        case insecureURL

        public var errorDescription: String? {
            switch self {
            case .unknownBundleID(let id):
                return "Bundle ID no soportado para actualizaciones: \(id)"
            case .missingChannelURL:
                return "El feed no incluye la URL del canal de esta app"
            case .missingSHA256:
                return "El feed no incluye SHA-256 del instalador"
            case .invalidURL:
                return "URL de actualización inválida"
            case .disallowedHost(let host):
                return "Host no permitido: \(host)"
            case .insecureURL:
                return "Solo se aceptan URLs HTTPS"
            }
        }
    }

    /// Elige el canal exclusivo del bundle instalado. Nunca mezcla Findaro ↔ Ordena.
    public static func resolve(
        feed: PublicFeed,
        installedBundleID: String
    ) throws -> ChannelRelease {
        let notes = try validatedHTTPSURL(feed.notes_url)

        let dmgString: String
        let sha: String
        let expectedID: String

        switch installedBundleID {
        case findaroBundleID:
            guard let url = feed.findaro_dmg_url, !url.isEmpty else {
                throw FeedError.missingChannelURL
            }
            guard let hash = feed.findaro_sha256, !hash.isEmpty else {
                throw FeedError.missingSHA256
            }
            dmgString = url
            sha = hash.lowercased()
            expectedID = findaroBundleID
        case ordenaBundleID:
            guard !feed.dmg_url.isEmpty else { throw FeedError.missingChannelURL }
            guard let hash = feed.sha256, !hash.isEmpty else { throw FeedError.missingSHA256 }
            dmgString = feed.dmg_url
            sha = hash.lowercased()
            expectedID = ordenaBundleID
        default:
            throw FeedError.unknownBundleID(installedBundleID)
        }

        let dmg = try validatedHTTPSURL(dmgString)
        return ChannelRelease(
            version: feed.version,
            tag: feed.tag ?? "v\(feed.version)",
            dmgURL: dmg,
            notesURL: notes,
            sha256: sha,
            expectedBundleID: expectedID
        )
    }

    public static func validatedHTTPSURL(_ string: String) throws -> URL {
        guard let url = URL(string: string), let host = url.host?.lowercased() else {
            throw FeedError.invalidURL
        }
        guard url.scheme?.lowercased() == "https" else {
            throw FeedError.insecureURL
        }
        guard allowedHosts.contains(host) else {
            throw FeedError.disallowedHost(host)
        }
        return url
    }

    public static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(pa.count, pb.count)
        for i in 0 ..< n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
