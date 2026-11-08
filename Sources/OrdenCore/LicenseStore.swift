import Foundation
import IOKit

public enum HardwareID {
    public static func current() -> String {
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard platformExpert != 0 else { return "UNKNOWN-MAC" }
        defer { IOObjectRelease(platformExpert) }
        if let uuid = IORegistryEntryCreateCFProperty(platformExpert, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            return uuid.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "UNKNOWN-MAC"
    }
}

public enum LicenseState: Equatable, Sendable {
    case trial(daysRemaining: Int, expiresAt: Date)
    case trialExpired
    case proActive(key: String, tier: String, seats: Int, activeCount: Int)
    case revoked(message: String)

    public var isPro: Bool {
        if case .proActive = self { return true }
        return false
    }

    public var isUsable: Bool {
        switch self {
        case .proActive, .trial:
            return true
        case .trialExpired, .revoked:
            return false
        }
    }
}

public struct SignedLicensePayload: Codable, Sendable {
    public let v: Int
    public let plan: String
    public let tier: String?
    public let email: String?
    public let key: String
    public let seats: Int?
    public let machineId: String?
    public let exp: Int?
}

@MainActor
public final class LicenseStore: ObservableObject {
    public static let shared = LicenseStore()

    @Published public private(set) var state: LicenseState = .trialExpired
    @Published public private(set) var isBusy: Bool = false
    @Published public private(set) var lastErrorMessage: String?

    private let defaults: UserDefaults
    private let serverURL = URL(string: "https://findaro.iareal.net")!

    private enum Keys {
        static let licenseKey = "findaro.license.key"
        static let signedToken = "findaro.license.token"
        static let trialStart = "findaro.trial.start"
        static let tier = "findaro.license.tier"
        static let seats = "findaro.license.seats"
        static let activeCount = "findaro.license.active_count"
        static let revoked = "findaro.license.revoked"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        evaluateLocalState()
    }

    // MARK: - Local State Evaluation (Offline-First)

    public func evaluateLocalState() {
        if defaults.bool(forKey: Keys.revoked) {
            state = .revoked(message: "Esta licencia ha sido revocada remotamente.")
            return
        }

        if let token = defaults.string(forKey: Keys.signedToken),
           let payload = parseTokenPayload(token) {
            let key = defaults.string(forKey: Keys.licenseKey) ?? payload.key
            let tier = defaults.string(forKey: Keys.tier) ?? payload.tier ?? "personal"
            let seats = defaults.integer(forKey: Keys.seats) > 0 ? defaults.integer(forKey: Keys.seats) : (payload.seats ?? 2)
            let activeCount = defaults.integer(forKey: Keys.activeCount) > 0 ? defaults.integer(forKey: Keys.activeCount) : 1

            if payload.plan == "pro" {
                state = .proActive(key: key, tier: tier, seats: seats, activeCount: activeCount)
                return
            } else if payload.plan == "trial", let exp = payload.exp {
                let expiresAt = Date(timeIntervalSince1970: TimeInterval(exp))
                if expiresAt > Date() {
                    let diff = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
                    state = .trial(daysRemaining: max(1, diff), expiresAt: expiresAt)
                    return
                } else {
                    state = .trialExpired
                    return
                }
            }
        }

        // Si no hay token de licencia, calcular prueba local de 5 días
        var trialStart = defaults.object(forKey: Keys.trialStart) as? Date
        if trialStart == nil {
            let now = Date()
            defaults.set(now, forKey: Keys.trialStart)
            trialStart = now
        }

        let trialDuration: TimeInterval = 5 * 24 * 60 * 60
        let expiresAt = trialStart!.addingTimeInterval(trialDuration)

        if Date() < expiresAt {
            let diff = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
            state = .trial(daysRemaining: max(1, diff), expiresAt: expiresAt)
        } else {
            state = .trialExpired
        }
    }

    // MARK: - Online Actions

    public func activate(key: String) async throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedKey.isEmpty else {
            throw NSError(domain: "FindaroLicense", code: 400, userInfo: [NSLocalizedDescriptionKey: "Ingresa una clave de licencia válida"])
        }

        isBusy = true
        lastErrorMessage = nil
        defer { isBusy = false }

        let machineId = HardwareID.current()
        let machineName = Host.current().localizedName ?? "Mac"

        let body: [String: Any] = [
            "licenseKey": trimmedKey,
            "machineId": machineId,
            "machineName": machineName
        ]

        let url = serverURL.appendingPathComponent("api/license/verify")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "FindaroLicense", code: 500, userInfo: [NSLocalizedDescriptionKey: "Error de red"])
        }

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard http.statusCode == 200, let ok = json["ok"] as? Bool, ok, let responseData = json["data"] as? [String: Any] else {
            let errorMsg = (json["error"] as? String) ?? "No se pudo activar la licencia (código \(http.statusCode))"
            lastErrorMessage = errorMsg
            throw NSError(domain: "FindaroLicense", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        let signed = responseData["signed"] as? String ?? ""
        let tier = responseData["tier"] as? String ?? "personal"
        let seats = responseData["seats"] as? Int ?? 2
        let activeCount = responseData["activeCount"] as? Int ?? 1
        let plan = responseData["plan"] as? String ?? "pro"

        defaults.set(trimmedKey, forKey: Keys.licenseKey)
        defaults.set(signed, forKey: Keys.signedToken)
        defaults.set(tier, forKey: Keys.tier)
        defaults.set(seats, forKey: Keys.seats)
        defaults.set(activeCount, forKey: Keys.activeCount)
        defaults.set(false, forKey: Keys.revoked)

        if plan == "pro" {
            state = .proActive(key: trimmedKey, tier: tier, seats: seats, activeCount: activeCount)
        } else {
            evaluateLocalState()
        }
    }

    public func deactivate() async throws {
        guard let key = defaults.string(forKey: Keys.licenseKey) else { return }

        isBusy = true
        lastErrorMessage = nil
        defer { isBusy = false }

        let machineId = HardwareID.current()
        let body: [String: Any] = [
            "licenseKey": key,
            "machineId": machineId
        ]

        let url = serverURL.appendingPathComponent("api/license/deactivate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 12

        _ = try? await URLSession.shared.data(for: req)

        // Limpiar registro local
        defaults.removeObject(forKey: Keys.licenseKey)
        defaults.removeObject(forKey: Keys.signedToken)
        defaults.removeObject(forKey: Keys.tier)
        defaults.removeObject(forKey: Keys.seats)
        defaults.removeObject(forKey: Keys.activeCount)

        evaluateLocalState()
    }

    public func checkServerStatus() async {
        guard let key = defaults.string(forKey: Keys.licenseKey) else { return }
        let machineId = HardwareID.current()

        let body: [String: Any] = [
            "licenseKey": key,
            "machineId": machineId
        ]

        let url = serverURL.appendingPathComponent("api/license/verify")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else { return }

        if http.statusCode == 404 || http.statusCode == 403 {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let msg = (json["error"] as? String) ?? "Licencia revocada o no disponible."
            if msg.localizedCaseInsensitiveContains("revocad") {
                defaults.set(true, forKey: Keys.revoked)
                state = .revoked(message: msg)
            }
        } else if http.statusCode == 200 {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if let responseData = json["data"] as? [String: Any] {
                let seats = responseData["seats"] as? Int ?? 2
                let activeCount = responseData["activeCount"] as? Int ?? 1
                let tier = responseData["tier"] as? String ?? "personal"
                defaults.set(seats, forKey: Keys.seats)
                defaults.set(activeCount, forKey: Keys.activeCount)
                defaults.set(tier, forKey: Keys.tier)
                defaults.set(false, forKey: Keys.revoked)
                state = .proActive(key: key, tier: tier, seats: seats, activeCount: activeCount)
            }
        }
    }

    // MARK: - Private Helper

    private func parseTokenPayload(_ token: String) -> SignedLicensePayload? {
        let parts = token.split(separator: ".")
        guard parts.count == 3, parts[0] == "F1" else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(SignedLicensePayload.self, from: data)
    }
}
