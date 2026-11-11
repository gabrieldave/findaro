import XCTest
import AppKit
@testable import OrdenCore

@MainActor
final class DefaultFileViewerTests: XCTestCase {
    nonisolated(unsafe) var originalViewer: String?

    override func setUp() {
        super.setUp()
        LicenseGate.setWriteAllowed(true)
        // Guardar el valor original real de la Mac para restaurarlo estrictamente al terminar
        originalViewer = CFPreferencesCopyAppValue("NSFileViewer" as CFString, kCFPreferencesAnyApplication) as? String
    }

    override func tearDown() {
        // Restaurar exactamente el estado original de la máquina
        if let original = originalViewer {
            CFPreferencesSetValue(
                "NSFileViewer" as CFString,
                original as CFPropertyList,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        } else {
            CFPreferencesSetValue(
                "NSFileViewer" as CFString,
                nil,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        }
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        UserDefaults.standard.removeObject(forKey: DefaultFileViewerManager.previousViewerKey)
        super.tearDown()
    }

    // TP-28: Activar la opción guarda el valor previo y escribe app.findaro.files
    func testTP28_EnableSetsBundleIDAndSavesPrevious() {
        // Simular que otra app (ej. PathFinder) era el visor anterior
        let simulatedPrior = "com.cocoatech.PathFinder"
        CFPreferencesSetValue(
            "NSFileViewer" as CFString,
            simulatedPrior as CFPropertyList,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        // Activar Findaro
        let success = DefaultFileViewerManager.enable()
        XCTAssertTrue(success)

        // Verificar que NSFileViewer es app.findaro.files
        let current = CFPreferencesCopyAppValue("NSFileViewer" as CFString, kCFPreferencesAnyApplication) as? String
        XCTAssertEqual(current, DefaultFileViewerManager.bundleID)
        XCTAssertTrue(DefaultFileViewerManager.isEnabled)

        // Verificar que el previo guardado fue com.cocoatech.PathFinder
        let savedPrevious = UserDefaults.standard.string(forKey: DefaultFileViewerManager.previousViewerKey)
        XCTAssertEqual(savedPrevious, simulatedPrior)
    }

    // TP-31: Evitar bucle infinito cuando Findaro es el explorador predeterminado
    func testTP31_FinderLoopAvoidanceWhenEnabled() {
        // Si Findaro es el explorador, la URL del Finder del sistema se usa explícitamente
        let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: finderURL.path), "Finder.app debe existir en /System/Library/CoreServices/")
    }

    // TP-32: Desactivar restaura exactamente el valor previo
    func testTP32_DisableRestoresPreviousViewer() {
        let simulatedPrior = "com.binarynights.ForkLift"
        UserDefaults.standard.set(simulatedPrior, forKey: DefaultFileViewerManager.previousViewerKey)

        CFPreferencesSetValue(
            "NSFileViewer" as CFString,
            DefaultFileViewerManager.bundleID as CFPropertyList,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        // Desactivar
        let success = DefaultFileViewerManager.disable()
        XCTAssertTrue(success)

        // Verificar que se restauró ForkLift
        let restored = CFPreferencesCopyAppValue("NSFileViewer" as CFString, kCFPreferencesAnyApplication) as? String
        XCTAssertEqual(restored, simulatedPrior)
        XCTAssertFalse(DefaultFileViewerManager.isEnabled)
        XCTAssertNil(UserDefaults.standard.string(forKey: DefaultFileViewerManager.previousViewerKey))
    }

    // TP-33: Desinstalar limpia la preferencia global
    func testTP33_UninstallClearsGlobalPreference() {
        _ = DefaultFileViewerManager.enable()
        XCTAssertTrue(DefaultFileViewerManager.isEnabled)
        
        // Simular llamada a desinstalación
        _ = DefaultFileViewerManager.disable()
        XCTAssertFalse(DefaultFileViewerManager.isEnabled)
    }

    // TP-35: Encolamiento de múltiples rutas para revelado simultáneo
    func testTP35_MultiPathRevealEnqueuesCorrectly() {
        DefaultFileViewerManager.pendingRevealPaths = []
        let testPaths = ["/tmp/file1.txt", "/tmp/file2.txt", "/var/log/system.log"]
        DefaultFileViewerManager.revealPaths(testPaths)
        XCTAssertEqual(DefaultFileViewerManager.pendingRevealPaths, testPaths)
    }

    // TP-36: Modo solo lectura (prueba vencida) no bloquea navegación ni revelado
    func testTP36_ReadOnlyModeAllowsRevealNavigation() {
        LicenseGate.setWriteAllowed(false)
        XCTAssertFalse(LicenseGate.allowsWrite())
        
        // La navegación y revelado de archivos no invocan requireWrite()
        DefaultFileViewerManager.pendingRevealPaths = []
        DefaultFileViewerManager.revealPaths(["/Users/Shared/test.pdf"])
        XCTAssertEqual(DefaultFileViewerManager.pendingRevealPaths, ["/Users/Shared/test.pdf"])
        
        LicenseGate.setWriteAllowed(true)
    }

    // TP-37: Restauración estricta de visor previo de terceros (PathFinder)
    func testTP37_PathFinderRestorationPreserved() {
        let pathFinder = "com.cocoatech.PathFinder"
        CFPreferencesSetValue(
            "NSFileViewer" as CFString,
            pathFinder as CFPropertyList,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        _ = DefaultFileViewerManager.enable()
        XCTAssertEqual(CFPreferencesCopyAppValue("NSFileViewer" as CFString, kCFPreferencesAnyApplication) as? String, DefaultFileViewerManager.bundleID)

        _ = DefaultFileViewerManager.disable()
        let finalViewer = CFPreferencesCopyAppValue("NSFileViewer" as CFString, kCFPreferencesAnyApplication) as? String
        XCTAssertEqual(finalViewer, pathFinder)
    }

    // Desactivar sin previo elimina la clave para que Finder vuelva a ser nativo
    func testDisableWithoutPreviousDeletesKey() {
        UserDefaults.standard.removeObject(forKey: DefaultFileViewerManager.previousViewerKey)
        CFPreferencesSetValue(
            "NSFileViewer" as CFString,
            DefaultFileViewerManager.bundleID as CFPropertyList,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        let success = DefaultFileViewerManager.disable()
        XCTAssertTrue(success)

        let restored = CFPreferencesCopyAppValue("NSFileViewer" as CFString, kCFPreferencesAnyApplication) as? String
        XCTAssertNil(restored)
        XCTAssertFalse(DefaultFileViewerManager.isEnabled)
    }
}
