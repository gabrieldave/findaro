import XCTest
@testable import OrdenCore

final class SmartFolderTests: XCTestCase {
    private func entry(
        _ name: String,
        dir: Bool = false,
        added: Date = Date(),
        created: Date? = nil
    ) -> FileEntry {
        FileEntry(
            path: "/tmp/\(name)",
            name: name,
            isDirectory: dir,
            size: 10,
            dateModified: added,
            dateCreated: created ?? added,
            dateAdded: added,
            kind: "x"
        )
    }

    func testCategoryMatch() {
        let pdfs = SmartFolder(name: "PDF", rootPath: "/tmp", categories: [.pdf])
        XCTAssertTrue(pdfs.matches(entry("factura.pdf")))
        XCTAssertTrue(pdfs.matches(entry("FACTURA.PDF")))
        XCTAssertFalse(pdfs.matches(entry("foto.png")))
        XCTAssertFalse(pdfs.matches(entry("Carpeta.pdf", dir: true)))
    }

    func testExtensionsAreAddedToCategories() {
        let folder = SmartFolder(name: "Mix", rootPath: "/tmp", categories: [.image], extensions: ["zip"])
        XCTAssertTrue(folder.matches(entry("a.png")))
        XCTAssertTrue(folder.matches(entry("b.zip")))
        XCTAssertFalse(folder.matches(entry("c.rar")))
    }

    func testAnyExtensionEvenUnknown() {
        let folder = SmartFolder(name: "MQ4", rootPath: "/tmp", extensions: SmartFolder.parseExtensions(".ex4, *.set"))
        XCTAssertEqual(folder.extensions, ["ex4", "set"])
        XCTAssertTrue(folder.matches(entry("Indicador.ex4")))
        XCTAssertTrue(folder.matches(entry("perfil.SET")))
        XCTAssertFalse(folder.matches(entry("perfil.txt")))
        XCTAssertFalse(folder.matches(entry("sinextension")))
    }

    func testParseExtensions() {
        XCTAssertEqual(SmartFolder.parseExtensions(" .ZIP, rar  7z;*.tar.gz, zip"), ["zip", "rar", "7z", "gz"])
        XCTAssertEqual(SmartFolder.parseExtensions(""), [])
        XCTAssertEqual(SmartFolder.parseExtensions(" , ; "), [])
    }

    func testCriteriaFromSearchText() {
        XCTAssertEqual(SmartFolder.criteria(fromSearchText: "*.pdf").extensions, ["pdf"])
        XCTAssertEqual(SmartFolder.criteria(fromSearchText: "PDF").extensions, ["pdf"])
        XCTAssertEqual(SmartFolder.criteria(fromSearchText: "zip").extensions, ["zip"])
        XCTAssertEqual(SmartFolder.criteria(fromSearchText: "Imágenes").categories, [.image])
        XCTAssertEqual(SmartFolder.criteria(fromSearchText: "fotos").categories, [.image])
        let free = SmartFolder.criteria(fromSearchText: "factura marzo")
        XCTAssertEqual(free.nameContains, "factura marzo")
        XCTAssertTrue(free.extensions.isEmpty)
        XCTAssertEqual(SmartFolder.criteria(fromSearchText: "vibe").nameContains, "vibe")
        XCTAssertTrue(SmartFolder.criteria(fromSearchText: "  ").nameContains.isEmpty)
    }

    func testNameContainsIgnoresCaseAndWildcards() {
        let folder = SmartFolder(name: "Facturas", rootPath: "/tmp", nameContains: "*Factura*")
        XCTAssertTrue(folder.matches(entry("Mi factura marzo.pdf")))
        XCTAssertFalse(folder.matches(entry("recibo.pdf")))
    }

    func testDownloadedTodayIncludesFoldersOnlyAtOneLevel() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        var today = SmartFolder(name: "Hoy", rootPath: "/tmp", dateWindow: .today)
        XCTAssertTrue(today.matches(entry("nuevo.zip", added: now), now: now))
        XCTAssertTrue(today.matches(entry("Carpeta", dir: true, added: now), now: now))
        XCTAssertFalse(today.matches(entry("viejo.zip", added: yesterday), now: now))
        // Algunos navegadores dejan «creado» = momento de descarga.
        XCTAssertTrue(today.matches(entry("navegador.dmg", added: yesterday, created: now), now: now))

        today.includeSubfolders = true
        XCTAssertFalse(today.matches(entry("Carpeta", dir: true, added: now), now: now))
    }

    func testAllCriteriaCombineWithAnd() {
        let now = Date()
        let old = Calendar.current.date(byAdding: .day, value: -40, to: now)!
        let folder = SmartFolder(
            name: "Fotos playa",
            rootPath: "/tmp",
            categories: [.image],
            nameContains: "playa",
            dateWindow: .lastDays(30)
        )
        XCTAssertTrue(folder.matches(entry("playa1.jpg", added: now), now: now))
        XCTAssertFalse(folder.matches(entry("playa1.jpg", added: old), now: now))
        XCTAssertFalse(folder.matches(entry("monte.jpg", added: now), now: now))
        XCTAssertFalse(folder.matches(entry("playa.pdf", added: now), now: now))
    }

    func testHasCriteria() {
        XCTAssertFalse(SmartFolder(name: "x", rootPath: "/tmp").hasCriteria)
        XCTAssertFalse(SmartFolder(name: "x", rootPath: "/tmp", nameContains: " * ").hasCriteria)
        XCTAssertTrue(SmartFolder(name: "x", rootPath: "/tmp", extensions: ["zip"]).hasCriteria)
        XCTAssertTrue(SmartFolder(name: "x", rootPath: "/tmp", dateWindow: .today).hasCriteria)
    }

    func testCodableRoundTripAndTolerantDecode() throws {
        let folder = SmartFolder(
            name: "ZIP",
            rootPath: "/Users/x/Downloads",
            includeSubfolders: true,
            categories: [.archive],
            extensions: ["iso"],
            nameContains: "backup",
            dateWindow: .lastDays(7)
        )
        let data = try JSONEncoder().encode(folder)
        let back = try JSONDecoder().decode(SmartFolder.self, from: data)
        XCTAssertEqual(back, folder)

        let minimal = #"{"name":"Solo nombre","rootPath":"/tmp"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SmartFolder.self, from: minimal)
        XCTAssertEqual(decoded.name, "Solo nombre")
        XCTAssertTrue(decoded.categories.isEmpty)
        XCTAssertNil(decoded.dateWindow)
    }

    func testPreferencesKeepSmartFolders() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PreferencesStore(directory: dir)
        let folder = SmartFolder(name: "PDF", rootPath: "/tmp", categories: [.pdf])
        store.update { $0.smartFolders = [folder] }

        let reopened = PreferencesStore(directory: dir)
        XCTAssertEqual(reopened.preferences.smartFolders, [folder])
    }

    func testOldPreferencesWithoutSmartFoldersStillLoad() throws {
        let json = #"{"schemaVersion":17,"favorites":["/tmp"]}"#.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(OrdenPreferences.self, from: json)
        XCTAssertEqual(prefs.smartFolders, [])
        XCTAssertEqual(prefs.favorites, ["/tmp"])
    }

    func testPresetDownloadedTodayPointsToDownloads() {
        let draft = SmartFolder(name: "", rootPath: "/tmp", categories: [.pdf])
        let applied = SmartFolder.Preset.downloadedToday.apply(to: draft, homePath: "/Users/demo")
        XCTAssertEqual(applied.rootPath, "/Users/demo/Downloads")
        XCTAssertEqual(applied.dateWindow, .today)
        XCTAssertTrue(applied.categories.isEmpty)
        XCTAssertFalse(applied.name.isEmpty)
    }

    func testSearchCollectsInSubfoldersOnlyWhenAsked() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("smart-\(UUID().uuidString)")
        let sub = root.appendingPathComponent("Sub/Deep")
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("a".utf8).write(to: root.appendingPathComponent("top.pdf"))
        try Data("a".utf8).write(to: sub.appendingPathComponent("deep.pdf"))
        try Data("a".utf8).write(to: sub.appendingPathComponent("photo.png"))

        var folder = SmartFolder(name: "PDF", rootPath: root.path, categories: [.pdf])
        let flat = SmartFolderSearch.collect(folder: folder, root: root.path)
        XCTAssertEqual(Set(flat.entries.map(\.name)), ["top.pdf"])

        folder.includeSubfolders = true
        let deep = SmartFolderSearch.collect(folder: folder, root: root.path)
        XCTAssertEqual(Set(deep.entries.map(\.name)), ["top.pdf", "deep.pdf"])
        XCTAssertFalse(deep.truncated)

        let capped = SmartFolderSearch.collect(folder: folder, root: root.path, maxResults: 1)
        XCTAssertEqual(capped.entries.count, 1)
        XCTAssertTrue(capped.truncated)
    }
}
