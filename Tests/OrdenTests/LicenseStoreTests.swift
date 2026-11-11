import XCTest
import CryptoKit
@testable import OrdenCore

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(_ initial: Date) {
        self._now = initial
    }

    var now: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _now
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _now = newValue
        }
    }
}

final class LicenseStoreTests: XCTestCase {
    var tempDefaults: UserDefaults!
    var suiteName: String!
    var mockKeychain: InMemoryKeychainStore!

    // Par de claves EFÍMERO generado en cada ejecución. Nunca usar aquí la clave de producción
    // (antes este archivo contenía la privada real: cualquiera con el repo podía crear licencias).
    let testSigningKey = Curve25519.Signing.PrivateKey()
    var testPublicKeyHex: String {
        testSigningKey.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
    }

    override func setUp() {
        super.setUp()
        suiteName = "test.findaro.license.\(UUID().uuidString)"
        tempDefaults = UserDefaults(suiteName: suiteName)!
        mockKeychain = InMemoryKeychainStore()
    }

    override func tearDown() {
        LicenseGate.setWriteAllowed(true)
        tempDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func hexToData(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        return data
    }

    private func mintSignedTestToken(
        plan: String = "pro",
        tier: String = "personal",
        key: String = "FINDARO-TEST-1234",
        seats: Int = 2,
        machineId: String? = HardwareID.current(),
        exp: Int? = nil
    ) -> String {
        let payload = SignedLicensePayload(
            v: 1,
            plan: plan,
            tier: tier,
            email: "tester@findaro.com",
            key: key,
            seats: seats,
            machineId: machineId,
            exp: exp
        )
        let jsonData = try! JSONEncoder().encode(payload)
        let bodyB64 = jsonData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let privKey = testSigningKey
        let sigData = try! privKey.signature(for: bodyB64.data(using: .utf8)!)
        let sigB64 = sigData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        return "F1.\(bodyB64).\(sigB64)"
    }

    @MainActor
    func testHardwareIDIsNotEmpty() {
        let id = HardwareID.current()
        XCTAssertFalse(id.isEmpty)
    }

    @MainActor
    func testInitialStateIsTrialWithDaysRemaining() {
        let store = LicenseStore(defaults: tempDefaults, keychain: mockKeychain)
        switch store.state {
        case .trial(let days, _):
            XCTAssertGreaterThanOrEqual(days, 1)
            XCTAssertLessThanOrEqual(days, 14)
            XCTAssertTrue(store.state.isUsable)
        default:
            XCTFail("Expected trial state on clean launch, got: \(store.state)")
        }
    }

    // TP-06: Vencimiento simulado con reloj inyectado
    @MainActor
    func testTrialExpiredWhenSimulatedClockExceeds5Days() {
        let startTime = Date()
        let clock = TestClock(startTime)

        let store = LicenseStore(
            defaults: tempDefaults,
            keychain: mockKeychain,
            dateProvider: { clock.now }
        )

        // Al inicio, dentro de los 14 días
        XCTAssertTrue(store.state.isUsable)

        // Avanzar el reloj simulado a 15 días en el futuro
        clock.now = startTime.addingTimeInterval(15 * 24 * 60 * 60)
        store.evaluateLocalState()

        XCTAssertEqual(store.state, .trialExpired)
        XCTAssertFalse(store.state.isUsable)
    }

    // TP-07: Token falso o manipulado es rechazado (firma criptográfica Ed25519)
    @MainActor
    func testForgedTokenIsRejected() {
        // Token manipulado con firma falsa tipo F1.<payload>.firma-falsa
        let payloadJson = #"{"v":1,"plan":"pro","tier":"family","key":"FINDARO-FAKE","seats":5}"#
        let bodyB64 = Data(payloadJson.utf8).base64EncodedString()
        let forgedToken = "F1.\(bodyB64).firma_falsa_invalida_12345678901234567890"

        tempDefaults.set(forgedToken, forKey: LicenseStore.Keys.signedToken)
        tempDefaults.set("FINDARO-FAKE", forKey: LicenseStore.Keys.licenseKey)

        let store = LicenseStore(defaults: tempDefaults, keychain: mockKeychain)

        // No debe ser proActive
        XCTAssertFalse(store.state.isPro)
        // El token manipulado debe haber sido eliminado
        XCTAssertNil(tempDefaults.string(forKey: LicenseStore.Keys.signedToken))
    }

    @MainActor
    func testTokenWithMismatchedMachineIdIsRejected() {
        let mismatchedToken = mintSignedTestToken(machineId: "DIFFERENT-MAC-HARDWARE-ID")
        tempDefaults.set(mismatchedToken, forKey: LicenseStore.Keys.signedToken)

        let store = LicenseStore(defaults: tempDefaults, keychain: mockKeychain, publicKeyHex: testPublicKeyHex)
        XCTAssertFalse(store.state.isPro)
    }

    @MainActor
    func testValidSignedEd25519TokenIsAccepted() {
        let validToken = mintSignedTestToken(plan: "pro", tier: "family", key: "FINDARO-VALID-1234", seats: 5)
        tempDefaults.set(validToken, forKey: LicenseStore.Keys.signedToken)
        tempDefaults.set("FINDARO-VALID-1234", forKey: LicenseStore.Keys.licenseKey)

        let store = LicenseStore(defaults: tempDefaults, keychain: mockKeychain, publicKeyHex: testPublicKeyHex)
        switch store.state {
        case .proActive(let key, let tier, let seats, _):
            XCTAssertEqual(key, "FINDARO-VALID-1234")
            XCTAssertEqual(tier, "family")
            XCTAssertEqual(seats, 5)
            XCTAssertTrue(store.state.isPro)
            XCTAssertTrue(store.state.isUsable)
        default:
            XCTFail("Expected proActive state for valid token, got: \(store.state)")
        }
    }

    // Un token Pro SIN machineId (como el de la página de gracias) no debe servir en ningún Mac.
    @MainActor
    func testTokenWithoutMachineIdIsRejected() {
        let unbound = mintSignedTestToken(machineId: nil)
        tempDefaults.set(unbound, forKey: LicenseStore.Keys.signedToken)
        let store = LicenseStore(defaults: tempDefaults, keychain: mockKeychain, publicKeyHex: testPublicKeyHex)
        XCTAssertFalse(store.state.isPro)
    }

    // Token firmado con la clave antigua/otra clave: rechazado aunque el formato sea perfecto.
    @MainActor
    func testTokenSignedWithOtherKeyIsRejected() {
        let token = mintSignedTestToken()
        tempDefaults.set(token, forKey: LicenseStore.Keys.signedToken)
        let store = LicenseStore(defaults: tempDefaults, keychain: mockKeychain) // clave embebida real
        XCTAssertFalse(store.state.isPro)
    }

    // Lease Pro caducado (más de 30 días sin conexión): pide revalidar, no queda Pro.
    @MainActor
    func testExpiredProLeaseRequiresRevalidation() {
        let past = Int(Date().addingTimeInterval(-60).timeIntervalSince1970)
        let token = mintSignedTestToken(exp: past)
        tempDefaults.set(token, forKey: LicenseStore.Keys.signedToken)
        tempDefaults.set("FINDARO-TEST-1234", forKey: LicenseStore.Keys.licenseKey)
        let store = LicenseStore(defaults: tempDefaults, keychain: mockKeychain, publicKeyHex: testPublicKeyHex)
        XCTAssertFalse(store.state.isUsable)
        if case .revoked = store.state {} else { XCTFail("Esperaba estado de revalidación, obtuve \(store.state)") }
    }

    // Atrasar el reloj del Mac no alarga la prueba.
    @MainActor
    func testRollingClockBackDoesNotExtendTrial() {
        let start = Date()
        let clock = TestClock(start)
        let store = LicenseStore(defaults: tempDefaults, keychain: mockKeychain, dateProvider: { clock.now })
        clock.now = start.addingTimeInterval(15 * 24 * 60 * 60)
        store.evaluateLocalState()
        XCTAssertEqual(store.state, .trialExpired)
        // El usuario atrasa el reloj al día 1.
        clock.now = start.addingTimeInterval(1 * 24 * 60 * 60)
        store.evaluateLocalState()
        XCTAssertEqual(store.state, .trialExpired)
    }

    // TP-08: Borrar findaro.trial.start de UserDefaults no reinicia la prueba (conservado en Keychain)
    @MainActor
    func testWipingUserDefaultsDoesNotResetTrialDueToKeychainPreservation() {
        let initialTime = Date().addingTimeInterval(-4 * 24 * 60 * 60) // Día 4
        let clock = TestClock(initialTime)

        _ = LicenseStore(
            defaults: tempDefaults,
            keychain: mockKeychain,
            dateProvider: { clock.now }
        )

        // Verificar que el inicio se registró en el Keychain
        let kcStart = mockKeychain.get(LicenseStore.Keys.trialStart)
        XCTAssertNotNil(kcStart)

        // Borrar findaro.trial.start de UserDefaults (simulando defaults delete)
        tempDefaults.removeObject(forKey: LicenseStore.Keys.trialStart)
        XCTAssertNil(tempDefaults.object(forKey: LicenseStore.Keys.trialStart))

        // Simular paso al día 15 desde el inicio original (fuera de los 14 días)
        clock.now = initialTime.addingTimeInterval(15 * 24 * 60 * 60)

        // Nuevo arranque: debe leer la fecha original del Keychain y detectar vencimiento
        let store2 = LicenseStore(
            defaults: tempDefaults,
            keychain: mockKeychain,
            dateProvider: { clock.now }
        )

        XCTAssertEqual(store2.state, .trialExpired, "Borrar preferencias no debe reiniciar el período de prueba")
        XCTAssertFalse(store2.state.isUsable)
    }

    // TP-20: LicenseGate bloquea todas las rutas del inventario de escritura en solo lectura
    func testLicenseGateBlocksWriteAndThrowsWhenNotAllowed() {
        LicenseGate.setWriteAllowed(false)
        XCTAssertFalse(LicenseGate.allowsWrite())

        XCTAssertThrowsError(try LicenseGate.requireWrite()) { error in
            guard let gateError = error as? LicenseGateError,
                  case .writeNotAllowed = gateError else {
                XCTFail("Se esperaba error writeNotAllowed, recibido: \(error)")
                return
            }
        }
    }

    func testWriteInventoryMethodsBlockedWhenLicenseGateIsClosed() throws {
        LicenseGate.setWriteAllowed(false)
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("test-gate-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let testFile = tempDir.appendingPathComponent("sample.txt")
        try "test".write(to: testFile, atomically: true, encoding: .utf8)

        // 1. FileOps.transfer bloqueado
        XCTAssertThrowsError(try FileOps.transfer(paths: [testFile.path], toDirectory: tempDir.path, move: false))

        // 2. FileOps.createFolder bloqueado
        XCTAssertThrowsError(try FileOps.createFolder(named: "subfolder", in: tempDir.path))

        // 3. FileOps.createFile bloqueado
        XCTAssertThrowsError(try FileOps.createFile(named: "newfile.txt", in: tempDir.path))

        // 4. FileOps.rename bloqueado
        XCTAssertThrowsError(try FileOps.rename(path: testFile.path, to: "renamed.txt"))

        // 5. FileOps.duplicate bloqueado
        XCTAssertThrowsError(try FileOps.duplicate(path: testFile.path))

        // 6. TrashOps.permanentlyDelete bloqueado
        XCTAssertThrowsError(try TrashOps.permanentlyDelete(paths: [testFile.path]))

        // 7. TrashOps.emptyUserTrash bloqueado
        XCTAssertThrowsError(try TrashOps.emptyUserTrash())

        // 8. ArchiveOps.extract bloqueado
        XCTAssertThrowsError(try ArchiveOps.extract(archivePath: testFile.path))
    }
}
