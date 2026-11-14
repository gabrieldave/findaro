import XCTest
@testable import OrdenCore

final class FolderDropPolicyTests: XCTestCase {

    // MARK: - Favoritos (carpeta actual, sin selección)

    func testFavoritesToggleAddsCurrentDirectoryCanonically() {
        let current = "/Users/testuser/Documents/Proyecto/"
        let normalized = "/Users/testuser/Documents/Proyecto"

        var favorites: [String] = []
        XCTAssertFalse(FavoritesPolicy.contains(favorites, path: current))

        let first = FavoritesPolicy.toggled(favorites, path: current)
        XCTAssertTrue(first.added)
        XCTAssertEqual(first.favorites, [normalized])
        favorites = first.favorites

        // La estrella ya es "star.fill" para la misma carpeta con otra forma de ruta.
        XCTAssertTrue(FavoritesPolicy.contains(favorites, path: "/Users/testuser/Documents/Proyecto"))
        XCTAssertTrue(FavoritesPolicy.contains(favorites, path: "/Users/testuser/Documents/./Proyecto/"))
    }

    func testFavoritesToggleRemovesExistingEntry() {
        let favorites = ["/Users/testuser/Documents/Proyecto", "/Users/testuser/Desktop"]
        let result = FavoritesPolicy.toggled(favorites, path: "/Users/testuser/Documents/Proyecto/")

        XCTAssertFalse(result.added)
        XCTAssertEqual(result.favorites, ["/Users/testuser/Desktop"])
    }

    func testFavoritesToggleNeverDuplicates() {
        var favorites: [String] = []
        favorites = FavoritesPolicy.toggled(favorites, path: "/Users/testuser/Music").favorites
        let second = FavoritesPolicy.toggled(favorites, path: "/Users/testuser/Music/")

        XCTAssertFalse(second.added)
        XCTAssertTrue(second.favorites.isEmpty)
    }

    func testFavoritesCanonicalHandlesDotDot() {
        let canonical = FavoritesPolicy.canonical("/Users/testuser/Documents/../Music/")
        XCTAssertEqual(canonical, "/Users/testuser/Music")
        XCTAssertTrue(FavoritesPolicy.contains(["/Users/testuser/Music"], path: canonical))
    }

    // MARK: - Destino del drop (carpeta/subcarpeta, sin Bandeja)

    func testDropDestinationUsesPanelFolderWhenNoRowHovered() {
        let dest = FolderDropPolicy.destination(
            panelDirectory: "/Users/testuser/Downloads/",
            hoveredFolder: nil
        )
        XCTAssertEqual(dest, "/Users/testuser/Downloads")
    }

    func testDropDestinationUsesHoveredSubfolder() {
        let dest = FolderDropPolicy.destination(
            panelDirectory: "/Users/testuser/Downloads",
            hoveredFolder: "/Users/testuser/Downloads/Proyectos/"
        )
        XCTAssertEqual(dest, "/Users/testuser/Downloads/Proyectos")
    }

    func testFilteredPathsDropsSelfDescendantsAndRedundantSources() {
        let dest = "/Users/testuser/Downloads"
        let paths = [
            "/Users/testuser/Downloads",              // el propio destino
            "/Users/testuser/Downloads/Proyectos",    // hijo (padre == destino)
            "/Users/testuser",                        // ancestro del destino
            "/Users/testuser/Desktop/a.txt",          // válido
            "/Users/testuser/Desktop/a.txt",          // duplicado
            "/Users/testuser/Desktop/./b.txt",        // válido, se canonicaliza
        ]

        let filtered = FolderDropPolicy.filteredPaths(paths, destination: dest)
        XCTAssertEqual(filtered, [
            "/Users/testuser/Desktop/a.txt",
            "/Users/testuser/Desktop/b.txt",
        ])
    }

    func testFilteredPathsKeepsEmptyListWithoutCrashing() {
        XCTAssertTrue(FolderDropPolicy.filteredPaths([], destination: "/Users/testuser").isEmpty)
    }

    // MARK: - Política Mover vs Copiar

    func testOptionAlwaysCopies() {
        XCTAssertEqual(
            FolderDropPolicy.intent(optionHeld: true, commandHeld: false, sourceAllowsMove: true, sameVolume: true),
            .copy
        )
    }

    func testSameVolumeMovesByDefault() {
        XCTAssertEqual(
            FolderDropPolicy.intent(optionHeld: false, commandHeld: false, sourceAllowsMove: true, sameVolume: true),
            .move
        )
    }

    func testDifferentVolumeWithoutCommandCopies() {
        XCTAssertEqual(
            FolderDropPolicy.intent(optionHeld: false, commandHeld: false, sourceAllowsMove: true, sameVolume: false),
            .copy
        )
    }

    func testDifferentVolumeWithCommandMoves() {
        XCTAssertEqual(
            FolderDropPolicy.intent(optionHeld: false, commandHeld: true, sourceAllowsMove: true, sameVolume: false),
            .move
        )
    }

    func testSourceWithoutMoveCopies() {
        XCTAssertEqual(
            FolderDropPolicy.intent(optionHeld: false, commandHeld: false, sourceAllowsMove: false, sameVolume: true),
            .copy
        )
    }

    func testSameVolumeDetectionForCurrentFolder() {
        let path = NSTemporaryDirectory()
        XCTAssertTrue(FolderDropPolicy.sameVolume(path, path))
        XCTAssertTrue(FolderDropPolicy.sameVolume("/", "/private/tmp"))
    }
}
