import XCTest
import OrdenCore

final class ListColumnFitTests: XCTestCase {
    func testNameBudgetDropsLowerPriorityColumns() {
        let preferred: [ListColumn] = [.dateAdded, .dateModified, .dateCreated, .size]
        // Panel ~518 pt: budget = 518 - 220 - 38 = 260 → size(72+12) + dateAdded(132+12) ≈ 228; no caben 3 fechas.
        let fitted = ListColumn.fit(preferred: preferred, budget: 260, compact: true)
        XCTAssertTrue(fitted.contains(.size))
        XCTAssertTrue(fitted.contains(.dateAdded))
        XCTAssertFalse(fitted.contains(.dateCreated))
        // Orden del usuario preservado entre las que caben.
        XCTAssertEqual(fitted.first, .dateAdded)
        XCTAssertEqual(fitted.last, .size)
    }

    func testWideBudgetKeepsAllPreferred() {
        let preferred: [ListColumn] = [.kind, .dateAdded, .size]
        let fitted = ListColumn.fit(preferred: preferred, budget: 900, compact: false)
        XCTAssertEqual(fitted, preferred)
    }

    func testTinyBudgetMayKeepOnlySize() {
        let preferred: [ListColumn] = [.dateAdded, .dateModified, .size]
        let fitted = ListColumn.fit(preferred: preferred, budget: 90, compact: true)
        XCTAssertEqual(fitted, [.size])
    }
}
