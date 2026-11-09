import XCTest
import AppKit
@testable import OrdenCore

@MainActor
final class DefaultFileViewerTests: XCTestCase {
    nonisolated(unsafe) var originalViewer: String?

    override func setUp() {
        super.setUp()
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
    func testEnableSetsBundleIDAndSavesPrevious() {
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

    // TP-32 & TP-37: Desactivar restaura exactamente el valor previo
    func testDisableRestoresPreviousViewer() {
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

    // TP-35: Encolamiento de rutas para revelado
    func testPendingRevealPathsEnqueuesCorrectly() {
        DefaultFileViewerManager.pendingRevealPaths = []
        let testPaths = ["/tmp/file1.txt", "/tmp/file2.txt"]
        DefaultFileViewerManager.revealPaths(testPaths)
        XCTAssertEqual(DefaultFileViewerManager.pendingRevealPaths, testPaths)
    }
}
