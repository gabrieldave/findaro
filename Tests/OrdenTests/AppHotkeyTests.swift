import XCTest
@testable import OrdenCore

final class AppHotkeyTests: XCTestCase {
    func testCatalogHasUniqueIds() {
        let ids = AppHotkeyCatalog.catalog.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertFalse(ids.isEmpty)
    }

    func testDefaultChordResolvesWithoutOverrides() {
        let chord = AppHotkeyCatalog.resolvedChord(id: "nav.back", overrides: [:])
        XCTAssertEqual(chord?.character, "1")
        XCTAssertEqual(chord?.command, true)
    }

    func testOverrideWins() {
        let custom = KeyChord(keyCode: 12, character: "q", command: true, option: true)
        let chord = AppHotkeyCatalog.resolvedChord(
            id: "nav.back",
            overrides: ["nav.back": custom]
        )
        XCTAssertEqual(chord, custom)
    }

    func testMatchesIgnoresUnrelatedModifiers() {
        let chord = KeyChord(keyCode: 123, option: true)
        XCTAssertTrue(chord.matches(
            keyCode: 123,
            characters: "",
            command: false,
            option: true,
            shift: false,
            control: false
        ))
        XCTAssertFalse(chord.matches(
            keyCode: 123,
            characters: "",
            command: true,
            option: true,
            shift: false,
            control: false
        ))
    }

    func testDisplayLabelIncludesSymbols() {
        let chord = KeyChord(keyCode: 46, character: "m", command: true, shift: true)
        XCTAssertTrue(chord.displayLabel.contains("⌘"))
        XCTAssertTrue(chord.displayLabel.contains("⇧"))
        XCTAssertTrue(chord.displayLabel.contains("M"))
    }
}
