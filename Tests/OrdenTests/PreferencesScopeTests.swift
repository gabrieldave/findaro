import XCTest
import OrdenCore

final class PreferencesScopeTests: XCTestCase {
    func testFolderOverrideBeatsGlobal() {
        let prefs = OrdenPreferences(
            schemaVersion: 8,
            globalRule: .downloads,
            folderOverrides: [
                "/tmp/proyectos": .projects
            ]
        )
        XCTAssertEqual(prefs.rule(for: "/tmp/otra"), .downloads)
        XCTAssertEqual(prefs.rule(for: "/tmp/proyectos"), .projects)
        XCTAssertTrue(prefs.hasOverride(for: "/tmp/proyectos"))
        XCTAssertFalse(prefs.hasOverride(for: "/tmp/otra"))
    }

    func testEverywhereClearsOverridesConceptually() {
        var prefs = OrdenPreferences(
            globalRule: .projects,
            folderOverrides: ["/a": .byType, "/b": .newestAddedFirst]
        )
        prefs.globalRule = .downloads
        prefs.folderOverrides = [:]
        XCTAssertEqual(prefs.rule(for: "/a"), .downloads)
        XCTAssertEqual(prefs.rule(for: "/b"), .downloads)
    }

    @MainActor
    func testPreferencesStoreReloadAndNotification() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeA = PreferencesStore(directory: tempDir)
        let storeB = PreferencesStore(directory: tempDir)

        let exp = expectation(description: "PreferencesDidChangeNotification fired")
        let observer = NotificationCenter.default.addObserver(
            forName: PreferencesStore.preferencesDidChangeNotification,
            object: nil,
            queue: .main
        ) { note in
            if (note.object as? PreferencesStore) === storeA {
                exp.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        storeA.update { prefs in
            prefs.globalRule = .projects
        }

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(storeA.preferences.globalRule, .projects)

        // Store B reloads from disk and sees the change
        let reloaded = storeB.reloadFromDisk()
        XCTAssertTrue(reloaded)
        XCTAssertEqual(storeB.preferences.globalRule, .projects)
    }
}
