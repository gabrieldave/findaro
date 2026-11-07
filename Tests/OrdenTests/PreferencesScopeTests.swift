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
}
