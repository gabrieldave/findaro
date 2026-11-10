import Foundation
import CryptoKit

/// Selección de canal de actualización según identidad del bundle instalado.
public enum UpdateFeed {
    public static let findaroBundleID = "app.findaro.files"
    public static let ordenaBundleID = "app.ordena.files"
    public static let allowedHosts: Set<String> = ["ordena.iareal.net"]

    /// Clave pública oficial Ed25519 para verificar latest.json firmado (32 bytes en hex).
    public static let updateSigningPublicKeyHex: String = "71393bb066067c8a5d35b737b683d6e10c941e5f2d19d9dd4fc51ccee0285334"

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
        case missingSignature
        case invalidSignature
        case invalidSigningKey
        case invalidFeedData

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
            case .missingSignature:
                return "Falta la firma digital de la actualización"
            case .invalidSignature:
                return "La firma digital de la actualización no es válida"
            case .invalidSigningKey:
                return "Clave pública de firma inválida"
            case .invalidFeedData:
                return "El formato del archivo de actualización es inválido"
            }
        }
    }

    public static func dataFromHex(_ hex: String) -> Data? {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count % 2 == 0 else { return nil }
        var data = Data(capacity: clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            guard let b = UInt8(clean[index..<nextIndex], radix: 16) else { return nil }
            data.append(b)
            index = nextIndex
        }
        return data
    }

    /// Verifica la firma Ed25519 sobre los bytes crudos del feed antes de decodificar el JSON.
    /// Acepta la firma como bytes crudos (64 bytes) o codificada en Base64.
    public static func verifiedFeed(
        data: Data,
        signature: Data,
        publicKeyHex: String = updateSigningPublicKeyHex
    ) throws -> PublicFeed {
        guard !signature.isEmpty else {
            throw FeedError.missingSignature
        }
        guard let pubKeyData = dataFromHex(publicKeyHex), pubKeyData.count == 32 else {
            throw FeedError.invalidSigningKey
        }
        let pubKey: Curve25519.Signing.PublicKey
        do {
            pubKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)
        } catch {
            throw FeedError.invalidSigningKey
        }

        let rawSignature: Data
        if signature.count == 64 {
            rawSignature = signature
        } else if let b64String = String(data: signature, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  let decoded = Data(base64Encoded: b64String),
                  decoded.count == 64 {
            rawSignature = decoded
        } else if let decoded = Data(base64Encoded: signature), decoded.count == 64 {
            rawSignature = decoded
        } else {
            throw FeedError.invalidSignature
        }

        guard pubKey.isValidSignature(rawSignature, for: data) else {
            throw FeedError.invalidSignature
        }

        do {
            return try JSONDecoder().decode(PublicFeed.self, from: data)
        } catch {
            throw FeedError.invalidFeedData
        }
    }

    /// Conveniencia: acepta la firma como String Base64.
    public static func verifiedFeed(
        data: Data,
        signatureBase64: String,
        publicKeyHex: String = updateSigningPublicKeyHex
    ) throws -> PublicFeed {
        let clean = signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let sigData = Data(base64Encoded: clean) else {
            throw FeedError.missingSignature
        }
        return try verifiedFeed(data: data, signature: sigData, publicKeyHex: publicKeyHex)
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
