import Foundation
import IOKit
import CryptoKit
import Security

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

public protocol KeychainStoreProtocol: Sendable {
    func get(_ key: String) -> String?
    func set(_ value: String, for key: String)
    func delete(_ key: String)
}

public struct SystemKeychainStore: KeychainStoreProtocol {
    public let service: String

    public init(service: String = "net.iareal.findaro") {
        self.service = service
    }

    public func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    public func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public final class InMemoryKeychainStore: KeychainStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    public init(initial: [String: String] = [:]) {
        self.storage = initial
    }

    public func get(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ value: String, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
    }

    public func delete(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
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

    public init(
        v: Int = 1,
        plan: String,
        tier: String? = nil,
        email: String? = nil,
        key: String,
        seats: Int? = nil,
        machineId: String? = nil,
        exp: Int? = nil
    ) {
        self.v = v
        self.plan = plan
        self.tier = tier
        self.email = email
        self.key = key
        self.seats = seats
        self.machineId = machineId
        self.exp = exp
    }
}

public enum FindaroLicenseVerifier {
    public static let embeddedPublicKeyHex = "6dd877795679418e21f4e19c116e5c02c68c7d58808cd3b330bc0c5b2e3c3bac"

    public static func hexToData(_ hex: String) -> Data? {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            guard let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) else { return nil }
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }

    public static func base64urlToData(_ str: String) -> Data? {
        var base64 = str.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        return Data(base64Encoded: base64)
    }

    public static func verifyToken(
        _ token: String,
        publicKeyHex: String = embeddedPublicKeyHex,
        expectedMachineId: String? = HardwareID.current(),
        currentDate: Date = Date()
    ) -> SignedLicensePayload? {
        let parts = token.split(separator: ".")
        guard parts.count == 3, (parts[0] == "F1" || parts[0] == "F2") else { return nil }
        let bodyString = String(parts[1])
        guard let sigData = base64urlToData(String(parts[2])), sigData.count == 64 else { return nil }
        guard let bodyData = bodyString.data(using: .utf8) else { return nil }
        guard let pubKeyData = hexToData(publicKeyHex), pubKeyData.count == 32 else { return nil }

        guard let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData) else { return nil }
        guard pubKey.isValidSignature(sigData, for: bodyData) else { return nil }

        guard let payloadData = base64urlToData(bodyString) else { return nil }
        guard let payload = try? JSONDecoder().decode(SignedLicensePayload.self, from: payloadData) else { return nil }

        // Si el payload contiene machineId, debe coincidir con este equipo
        if let tokenMachineId = payload.machineId, !tokenMachineId.isEmpty, let expected = expectedMachineId, !expected.isEmpty {
            if tokenMachineId != expected {
                return nil
            }
        }

        // Si el payload contiene exp, verificar que no haya expirado
        if let exp = payload.exp {
            let expirationDate = Date(timeIntervalSince1970: TimeInterval(exp))
            if expirationDate < currentDate {
                return nil
            }
        }

        return payload
    }
}

@MainActor
public final class LicenseStore: ObservableObject {
    public static let shared = LicenseStore()

    @Published public private(set) var state: LicenseState = .trialExpired {
        didSet {
            LicenseGate.setWriteAllowed(state.isUsable)
        }
    }
    @Published public private(set) var isBusy: Bool = false
    @Published public private(set) var lastErrorMessage: String?

    private let defaults: UserDefaults
    private let keychain: KeychainStoreProtocol
    private let dateProvider: @Sendable () -> Date
    private let serverURL = URL(string: "https://findaro.iareal.net")!
    private var periodicTask: Task<Void, Never>?

    public enum Keys {
        public static let licenseKey = "findaro.license.key"
        public static let signedToken = "findaro.license.token"
        public static let trialStart = "findaro.trial.start"
        public static let tier = "findaro.license.tier"
        public static let seats = "findaro.license.seats"
        public static let activeCount = "findaro.license.active_count"
        public static let revoked = "findaro.license.revoked"
        public static let lastVerifiedAt = "findaro.license.last_verified_at"
    }

    public init(
        defaults: UserDefaults = .standard,
        keychain: KeychainStoreProtocol = SystemKeychainStore(),
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.dateProvider = dateProvider
        evaluateLocalState()
        LicenseGate.setWriteAllowed(state.isUsable)
    }

    deinit {
        periodicTask?.cancel()
    }

    // MARK: - Local State Evaluation (Offline-First)

    public func evaluateLocalState() {
        if defaults.bool(forKey: Keys.revoked) {
            state = .revoked(message: "Esta licencia ha sido revocada remotamente.")
            return
        }

        let now = dateProvider()

        // 1. Verificar si existe token firmado en UserDefaults o Keychain
        let tokenCandidate = defaults.string(forKey: Keys.signedToken) ?? keychain.get(Keys.signedToken)
        if let token = tokenCandidate,
           let payload = FindaroLicenseVerifier.verifyToken(token, expectedMachineId: HardwareID.current(), currentDate: now) {
            // Asegurar sincronización en Keychain y UserDefaults
            defaults.set(token, forKey: Keys.signedToken)
            keychain.set(token, for: Keys.signedToken)

            let key = defaults.string(forKey: Keys.licenseKey) ?? keychain.get(Keys.licenseKey) ?? payload.key
            let tier = defaults.string(forKey: Keys.tier) ?? payload.tier ?? "personal"
            let seats = defaults.integer(forKey: Keys.seats) > 0 ? defaults.integer(forKey: Keys.seats) : (payload.seats ?? 2)
            let activeCount = defaults.integer(forKey: Keys.activeCount) > 0 ? defaults.integer(forKey: Keys.activeCount) : 1

            if payload.plan == "pro" {
                state = .proActive(key: key, tier: tier, seats: seats, activeCount: activeCount)
                return
            } else if payload.plan == "trial", let exp = payload.exp {
                let expiresAt = Date(timeIntervalSince1970: TimeInterval(exp))
                if expiresAt > now {
                    let diff = Calendar.current.dateComponents([.day], from: now, to: expiresAt).day ?? 0
                    state = .trial(daysRemaining: max(1, diff), expiresAt: expiresAt)
                    return
                } else {
                    state = .trialExpired
                    return
                }
            }
        } else if tokenCandidate != nil {
            // El token guardado era inválido, manipulado o expiró: descartarlo
            defaults.removeObject(forKey: Keys.signedToken)
            keychain.delete(Keys.signedToken)
        }

        // 2. Si no hay token de licencia, evaluar período de prueba local de 5 días
        // El inicio de prueba se guarda en Keychain para que borrar preferencias no lo reinicie
        var trialStart: Date?
        if let kcVal = keychain.get(Keys.trialStart), let ts = Double(kcVal) {
            trialStart = Date(timeIntervalSince1970: ts)
        } else if let defDate = defaults.object(forKey: Keys.trialStart) as? Date {
            trialStart = defDate
            keychain.set(String(defDate.timeIntervalSince1970), for: Keys.trialStart)
        }

        if trialStart == nil {
            trialStart = now
            defaults.set(now, forKey: Keys.trialStart)
            keychain.set(String(now.timeIntervalSince1970), for: Keys.trialStart)
        } else {
            // Si el usuario borró UserDefaults, restaurar la fecha original de Keychain
            defaults.set(trialStart!, forKey: Keys.trialStart)
        }

        let trialDuration: TimeInterval = 5 * 24 * 60 * 60
        let expiresAt = trialStart!.addingTimeInterval(trialDuration)

        if now < expiresAt {
            let diff = Calendar.current.dateComponents([.day], from: now, to: expiresAt).day ?? 0
            state = .trial(daysRemaining: max(1, diff), expiresAt: expiresAt)
        } else {
            state = .trialExpired
        }
    }

    // MARK: - Periodic Background Status Check (Every 24h with 14d offline tolerance)

    public func startPeriodicCheck() {
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkServerStatus()
                // Esperar 24 horas (86400 segundos)
                try? await Task.sleep(nanoseconds: 86_400_000_000_000)
            }
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

        // Verificar criptográficamente el token antes de aceptarlo y persistirlo
        guard let _ = FindaroLicenseVerifier.verifyToken(signed, expectedMachineId: machineId, currentDate: dateProvider()) else {
            let errorMsg = "La firma de la licencia devuelta por el servidor no es válida."
            lastErrorMessage = errorMsg
            throw NSError(domain: "FindaroLicense", code: 400, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        defaults.set(trimmedKey, forKey: Keys.licenseKey)
        defaults.set(signed, forKey: Keys.signedToken)
        defaults.set(tier, forKey: Keys.tier)
        defaults.set(seats, forKey: Keys.seats)
        defaults.set(activeCount, forKey: Keys.activeCount)
        defaults.set(false, forKey: Keys.revoked)
        defaults.set(dateProvider(), forKey: Keys.lastVerifiedAt)

        keychain.set(trimmedKey, for: Keys.licenseKey)
        keychain.set(signed, for: Keys.signedToken)

        if plan == "pro" {
            state = .proActive(key: key, tier: tier, seats: seats, activeCount: activeCount)
        } else {
            evaluateLocalState()
        }
    }

    public func deactivate() async throws {
        guard let key = defaults.string(forKey: Keys.licenseKey) ?? keychain.get(Keys.licenseKey) else { return }

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

        // Limpiar registro local en Defaults y Keychain
        defaults.removeObject(forKey: Keys.licenseKey)
        defaults.removeObject(forKey: Keys.signedToken)
        defaults.removeObject(forKey: Keys.tier)
        defaults.removeObject(forKey: Keys.seats)
        defaults.removeObject(forKey: Keys.activeCount)

        keychain.delete(Keys.licenseKey)
        keychain.delete(Keys.signedToken)

        evaluateLocalState()
    }

    public func checkServerStatus() async {
        guard let key = defaults.string(forKey: Keys.licenseKey) ?? keychain.get(Keys.licenseKey) else { return }
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
              let http = response as? HTTPURLResponse else {
            // Tolerancia sin conexión: si pasaron más de 14 días sin verificar, advertir o reevaluar
            if let lastDate = defaults.object(forKey: Keys.lastVerifiedAt) as? Date {
                let fourteenDays: TimeInterval = 14 * 24 * 60 * 60
                if dateProvider().timeIntervalSince(lastDate) > fourteenDays {
                    // Ha expirado la tolerancia offline de 14 días
                    print("[LicenseStore] Tolerancia offline de 14 días superada")
                }
            }
            return
        }

        if http.statusCode == 404 || http.statusCode == 403 {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let msg = (json["error"] as? String) ?? "Licencia revocada o no disponible."
            defaults.set(true, forKey: Keys.revoked)
            defaults.removeObject(forKey: Keys.signedToken)
            keychain.delete(Keys.signedToken)
            state = .revoked(message: msg)
        } else if http.statusCode == 200 {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if let responseData = json["data"] as? [String: Any] {
                let plan = responseData["plan"] as? String ?? "pro"
                let seats = responseData["seats"] as? Int ?? 2
                let activeCount = responseData["activeCount"] as? Int ?? 1
                let tier = responseData["tier"] as? String ?? "personal"
                let signed = responseData["signed"] as? String ?? ""

                // Validar token firmado si se devuelve
                if !signed.isEmpty, let _ = FindaroLicenseVerifier.verifyToken(signed, expectedMachineId: machineId, currentDate: dateProvider()) {
                    defaults.set(signed, forKey: Keys.signedToken)
                    keychain.set(signed, for: Keys.signedToken)
                }

                defaults.set(seats, forKey: Keys.seats)
                defaults.set(activeCount, forKey: Keys.activeCount)
                defaults.set(tier, forKey: Keys.tier)
                defaults.set(false, forKey: Keys.revoked)
                defaults.set(dateProvider(), forKey: Keys.lastVerifiedAt)

                if plan == "pro" {
                    state = .proActive(key: key, tier: tier, seats: seats, activeCount: activeCount)
                } else {
                    evaluateLocalState()
                }
            }
        }
    }
}
