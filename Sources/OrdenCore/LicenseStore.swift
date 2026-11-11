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
    /// Rotada el 2026-11-09: la anterior (6dd87779…) quedó comprometida (su privada estaba en el repo).
    /// Debe coincidir con FINDARO_ED25519_PUBLIC_KEY_HEX en web/src/lib/license.ts.
    public static let embeddedPublicKeyHex = "c86b663a1d94a3f69bee0b189b00c541c0c8e55b71c4ffdc166052ff57feb5dd"

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
        currentDate: Date = Date(),
        allowExpired: Bool = false
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

        // El token DEBE estar ligado a este Mac. Antes un token sin machineId (p. ej. el que se
        // emite en la página de gracias) servía en Macs ilimitadas copiándolo con `defaults write`.
        guard let tokenMachineId = payload.machineId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tokenMachineId.isEmpty,
              let expected = expectedMachineId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !expected.isEmpty,
              expected != "UNKNOWN-MAC",
              tokenMachineId.caseInsensitiveCompare(expected) == .orderedSame else {
            return nil
        }

        // Si el payload contiene exp, verificar que no haya expirado
        if !allowExpired, let exp = payload.exp {
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
    private let publicKeyHex: String
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
        /// Fecha más reciente observada (anti "atrasar el reloj" para alargar la prueba).
        public static let trialLastSeen = "findaro.trial.last_seen"
    }

    public static let trialDuration: TimeInterval = 14 * 24 * 60 * 60

    public init(
        defaults: UserDefaults = .standard,
        keychain: KeychainStoreProtocol = SystemKeychainStore(),
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        publicKeyHex: String = FindaroLicenseVerifier.embeddedPublicKeyHex
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.dateProvider = dateProvider
        self.publicKeyHex = publicKeyHex
        evaluateLocalState()
        LicenseGate.setWriteAllowed(state.isUsable)
    }

    deinit {
        periodicTask?.cancel()
    }

    // MARK: - Local State Evaluation (Offline-First)

    public func evaluateLocalState() {
        if defaults.bool(forKey: Keys.revoked) {
            state = .revoked(message: L10n.s(
                "Esta licencia ha sido revocada remotamente.",
                "This license has been revoked remotely."
            ))
            return
        }

        let now = dateProvider()

        // 1. Verificar si existe token firmado en UserDefaults o Keychain
        let tokenCandidate = defaults.string(forKey: Keys.signedToken) ?? keychain.get(Keys.signedToken)
        if let token = tokenCandidate,
           let payload = FindaroLicenseVerifier.verifyToken(token, publicKeyHex: publicKeyHex, expectedMachineId: HardwareID.current(), currentDate: now) {
            // Asegurar sincronización en Keychain y UserDefaults
            defaults.set(token, forKey: Keys.signedToken)
            keychain.set(token, for: Keys.signedToken)

            let key = defaults.string(forKey: Keys.licenseKey) ?? keychain.get(Keys.licenseKey) ?? payload.key
            let tier = defaults.string(forKey: Keys.tier) ?? payload.tier ?? "personal"
            // seats=1 (Personal) es licencia Pro válida; no forzar mínimo 2.
            let fallbackSeats = (payload.tier == "solo") ? 1 : 2
            let seatsFromPayload = payload.seats.flatMap { $0 >= 1 ? $0 : nil } ?? fallbackSeats
            let seats = defaults.integer(forKey: Keys.seats) > 0 ? defaults.integer(forKey: Keys.seats) : seatsFromPayload
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

        // Hay clave Pro guardada pero su token caducó (más de 30 días sin conexión) o es de la
        // clave de firma anterior: pedir conexión para revalidar (checkServerStatus lo renueva solo).
        let storedKey = defaults.string(forKey: Keys.licenseKey) ?? keychain.get(Keys.licenseKey)
        if storedKey != nil, defaults.string(forKey: Keys.tier) != "trial" {
            state = .revoked(message: L10n.s(
                "Tu licencia necesita revalidarse. Conéctate a internet y Findaro la renovará automáticamente.",
                "Your license needs revalidation. Connect to the internet and Findaro will renew it automatically."
            ))
            return
        }

        // 2. Si no hay token de licencia, evaluar período de prueba local de 14 días
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

        let expiresAt = trialStart!.addingTimeInterval(Self.trialDuration)

        // Anti-retroceso de reloj: usar la fecha más reciente que este Mac haya visto.
        var trialNow = now
        if let lastRaw = keychain.get(Keys.trialLastSeen), let last = Double(lastRaw) {
            let lastSeen = Date(timeIntervalSince1970: last)
            if lastSeen > trialNow { trialNow = lastSeen }
        }
        keychain.set(String(trialNow.timeIntervalSince1970), for: Keys.trialLastSeen)

        if trialNow < expiresAt {
            let diff = Calendar.current.dateComponents([.day], from: trialNow, to: expiresAt).day ?? 0
            state = .trial(daysRemaining: max(1, diff), expiresAt: expiresAt)
        } else {
            state = .trialExpired
        }
    }

    // MARK: - Prueba anclada en el servidor

    /// Pide al servidor la fecha real de inicio de la prueba de ESTE Mac (por hash de hardware).
    /// Si el usuario borró el Llavero o reinstaló, el servidor devuelve la fecha original y la
    /// prueba no se reinicia. Sin conexión, se mantiene la prueba local (offline-first).
    public func syncDeviceTrial() async {
        if state.isPro { return }
        if (defaults.string(forKey: Keys.licenseKey) ?? keychain.get(Keys.licenseKey)) != nil { return }

        let machineId = HardwareID.current()
        guard machineId != "UNKNOWN-MAC" else { return }

        var req = URLRequest(url: serverURL.appendingPathComponent("api/trial/device"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["machineId": machineId])
        req.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payloadJSON = json["data"] as? [String: Any],
              let signed = payloadJSON["signed"] as? String,
              let payload = FindaroLicenseVerifier.verifyToken(
                signed,
                publicKeyHex: publicKeyHex,
                expectedMachineId: machineId,
                currentDate: dateProvider(),
                allowExpired: true
              ),
              payload.plan == "trial",
              let exp = payload.exp else { return }

        // Inicio según el servidor; nos quedamos con el MÁS ANTIGUO entre local y servidor.
        let serverStart = Date(timeIntervalSince1970: TimeInterval(exp)).addingTimeInterval(-Self.trialDuration)
        var localStart: Date?
        if let kcVal = keychain.get(Keys.trialStart), let ts = Double(kcVal) {
            localStart = Date(timeIntervalSince1970: ts)
        }
        let effectiveStart = min(localStart ?? serverStart, serverStart)
        keychain.set(String(effectiveStart.timeIntervalSince1970), for: Keys.trialStart)
        defaults.set(effectiveStart, forKey: Keys.trialStart)
        evaluateLocalState()
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
            throw NSError(domain: "FindaroLicense", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.s(
                "Ingresa una clave de licencia válida",
                "Enter a valid license key"
            )])
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
            throw NSError(domain: "FindaroLicense", code: 500, userInfo: [NSLocalizedDescriptionKey: L10n.s(
                "Error de red",
                "Network error"
            )])
        }

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard http.statusCode == 200, let ok = json["ok"] as? Bool, ok, let responseData = json["data"] as? [String: Any] else {
            let errorMsg = (json["error"] as? String) ?? L10n.s(
                "No se pudo activar la licencia (código \(http.statusCode))",
                "Could not activate license (code \(http.statusCode))"
            )
            lastErrorMessage = errorMsg
            throw NSError(domain: "FindaroLicense", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        let signed = responseData["signed"] as? String ?? ""
        let tier = responseData["tier"] as? String ?? "personal"
        let seatsRaw = responseData["seats"] as? Int ?? (tier == "solo" ? 1 : 2)
        let seats = max(1, seatsRaw)
        let activeCount = responseData["activeCount"] as? Int ?? 1
        let plan = responseData["plan"] as? String ?? "pro"

        // Verificar criptográficamente el token antes de aceptarlo y persistirlo
        guard let _ = FindaroLicenseVerifier.verifyToken(signed, publicKeyHex: publicKeyHex, expectedMachineId: machineId, currentDate: dateProvider()) else {
            let errorMsg = L10n.s(
                "La firma de la licencia devuelta por el servidor no es válida.",
                "The license signature returned by the server is invalid."
            )
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

        // Solo el JSON de NUESTRA API cuenta (un 403/404 de un proxy, WAF o portal Wi-Fi
        // no debe revocar la licencia de un cliente que pagó).
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let isOurAPI = json["ok"] is Bool

        if http.statusCode == 404, isOurAPI {
            // Licencia inexistente o revocada en el servidor (reembolso, clave filtrada).
            let msg = (json["error"] as? String) ?? L10n.s(
                "Licencia revocada o no disponible.",
                "License revoked or unavailable."
            )
            defaults.set(true, forKey: Keys.revoked)
            defaults.removeObject(forKey: Keys.signedToken)
            keychain.delete(Keys.signedToken)
            state = .revoked(message: msg)
        } else if (http.statusCode == 403 || http.statusCode == 402), isOurAPI {
            // Límite de Macs alcanzado o prueba terminada: sin marca permanente de "revocada";
            // el usuario puede liberar un asiento y volver a activar.
            let msg = (json["error"] as? String) ?? L10n.s(
                "Esta Mac no está activada para esta licencia.",
                "This Mac is not activated for this license."
            )
            defaults.removeObject(forKey: Keys.signedToken)
            keychain.delete(Keys.signedToken)
            lastErrorMessage = msg
            state = .revoked(message: msg)
        } else if http.statusCode == 200 {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if let responseData = json["data"] as? [String: Any] {
                let plan = responseData["plan"] as? String ?? "pro"
                let tier = responseData["tier"] as? String ?? "personal"
                let seatsRaw = responseData["seats"] as? Int ?? (tier == "solo" ? 1 : 2)
                let seats = max(1, seatsRaw)
                let activeCount = responseData["activeCount"] as? Int ?? 1
                let signed = responseData["signed"] as? String ?? ""
                defaults.set(false, forKey: Keys.revoked)

                // Validar token firmado si se devuelve
                if !signed.isEmpty, let _ = FindaroLicenseVerifier.verifyToken(signed, publicKeyHex: publicKeyHex, expectedMachineId: machineId, currentDate: dateProvider()) {
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
