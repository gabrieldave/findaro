import XCTest
@testable import OrdenCore

final class RowHitTestLogicTests: XCTestCase {
    func testIndexAtYMatchesFixedRowHeight() {
        XCTAssertEqual(RowHitTestLogic.indexAtY(0, rowHeight: 48, count: 10), 0)
        XCTAssertEqual(RowHitTestLogic.indexAtY(47.9, rowHeight: 48, count: 10), 0)
        XCTAssertEqual(RowHitTestLogic.indexAtY(48, rowHeight: 48, count: 10), 1)
        XCTAssertEqual(RowHitTestLogic.indexAtY(96, rowHeight: 48, count: 10), 2)
        XCTAssertNil(RowHitTestLogic.indexAtY(-1, rowHeight: 48, count: 10))
        XCTAssertNil(RowHitTestLogic.indexAtY(480, rowHeight: 48, count: 10))
    }

    func testPathAtPicksContainingRow() {
        let gen: UInt64 = 3
        let frames = [
            RowHitTestLogic.RowFrame(path: "/a", frame: CGRect(x: 0, y: 100, width: 200, height: 48), generation: gen),
            RowHitTestLogic.RowFrame(path: "/b", frame: CGRect(x: 0, y: 148, width: 200, height: 48), generation: gen),
            RowHitTestLogic.RowFrame(path: "/c", frame: CGRect(x: 0, y: 196, width: 200, height: 48), generation: gen),
        ]
        XCTAssertEqual(
            RowHitTestLogic.pathAt(point: CGPoint(x: 40, y: 120), frames: frames, generation: gen),
            "/a"
        )
        XCTAssertEqual(
            RowHitTestLogic.pathAt(point: CGPoint(x: 40, y: 170), frames: frames, generation: gen),
            "/b"
        )
        XCTAssertEqual(
            RowHitTestLogic.pathAt(point: CGPoint(x: 40, y: 220), frames: frames, generation: gen),
            "/c"
        )
    }

    func testPathAtIgnoresStaleGeneration() {
        let frames = [
            RowHitTestLogic.RowFrame(path: "/stale", frame: CGRect(x: 0, y: 100, width: 200, height: 48), generation: 1),
            RowHitTestLogic.RowFrame(path: "/fresh", frame: CGRect(x: 0, y: 100, width: 200, height: 48), generation: 2),
        ]
        XCTAssertEqual(
            RowHitTestLogic.pathAt(point: CGPoint(x: 40, y: 120), frames: frames, generation: 2),
            "/fresh"
        )
        XCTAssertNil(
            RowHitTestLogic.pathAt(point: CGPoint(x: 40, y: 120), frames: frames, generation: 3)
        )
    }

    /// Caso real: tras scroll, frames viejos siguen “conteniendo” el clic y solapan.
    func testPathAtReturnsNilWhenOverlappingFramesAreAmbiguous() {
        let gen: UInt64 = 5
        let frames = [
            RowHitTestLogic.RowFrame(path: "/row1", frame: CGRect(x: 0, y: 200, width: 200, height: 48), generation: gen),
            // Frame fantasma (stale) casi en el mismo sitio — típico LazyVStack.
            RowHitTestLogic.RowFrame(path: "/row3", frame: CGRect(x: 0, y: 204, width: 200, height: 48), generation: gen),
        ]
        XCTAssertNil(
            RowHitTestLogic.pathAt(point: CGPoint(x: 50, y: 220), frames: frames, generation: gen)
        )
    }

    func testPathAtDoesNotJumpTwoRowsWhenOnlyOneFrameIsValid() {
        let gen: UInt64 = 9
        let frames = [
            RowHitTestLogic.RowFrame(path: "/only", frame: CGRect(x: 0, y: 300, width: 400, height: 64), generation: gen),
        ]
        XCTAssertEqual(
            RowHitTestLogic.pathAt(point: CGPoint(x: 20, y: 330), frames: frames, generation: gen),
            "/only"
        )
    }
}
