import XCTest
@testable import OrdenCore

final class PressDragSelectLogicTests: XCTestCase {
    func testUnselectedFileStartsPendingNotImmediateDrag() {
        let action = PressDragSelectLogic.startAction(
            hitID: "a",
            hitPath: "/tmp/a.pdf",
            hitIsSelected: false,
            selectedPaths: ["/tmp/other.zip"],
            commandHeld: false,
            shiftHeld: false,
            hasArmedFileDrag: false,
            armedPaths: [],
            isArming: false
        )
        XCTAssertEqual(action, .pendingUnselectedFile(id: "a", path: "/tmp/a.pdf"))
    }

    func testPendingVerticalBecomesMarquee() {
        let resolved = PressDragSelectLogic.resolvePendingUnselected(
            id: "a",
            path: "/tmp/a.pdf",
            translation: CGSize(width: 2, height: 30)
        )
        XCTAssertEqual(resolved, .beginMarquee(additive: false))
    }

    func testPendingHorizontalBecomesFileDrag() {
        let resolved = PressDragSelectLogic.resolvePendingUnselected(
            id: "a",
            path: "/tmp/a.pdf",
            translation: CGSize(width: 12, height: 3)
        )
        XCTAssertEqual(resolved, .beginFileDrag(paths: ["/tmp/a.pdf"], selectOnlyID: "a"))
    }

    func testPendingSmallMoveStaysUndecided() {
        let resolved = PressDragSelectLogic.resolvePendingUnselected(
            id: "a",
            path: "/tmp/a.pdf",
            translation: CGSize(width: 2, height: 10)
        )
        XCTAssertNil(resolved)
    }

    func testClickDragOnSelectedFileDragsWholeSelection() {
        let action = PressDragSelectLogic.startAction(
            hitID: "a",
            hitPath: "/tmp/a.pdf",
            hitIsSelected: true,
            selectedPaths: ["/tmp/a.pdf", "/tmp/b.pdf"],
            commandHeld: false,
            shiftHeld: false,
            hasArmedFileDrag: false,
            armedPaths: [],
            isArming: false
        )
        XCTAssertEqual(action, .beginFileDrag(paths: ["/tmp/a.pdf", "/tmp/b.pdf"], selectOnlyID: nil))
    }

    func testEmptySpaceStartsMarquee() {
        let action = PressDragSelectLogic.startAction(
            hitID: nil,
            hitPath: nil,
            hitIsSelected: false,
            selectedPaths: [],
            commandHeld: false,
            shiftHeld: false,
            hasArmedFileDrag: false,
            armedPaths: [],
            isArming: false
        )
        XCTAssertEqual(action, .beginMarquee(additive: false))
    }

    func testShiftOnUnselectedKeepsAdditiveMarquee() {
        let action = PressDragSelectLogic.startAction(
            hitID: "a",
            hitPath: "/tmp/a.pdf",
            hitIsSelected: false,
            selectedPaths: ["/tmp/b.pdf"],
            commandHeld: false,
            shiftHeld: true,
            hasArmedFileDrag: false,
            armedPaths: [],
            isArming: false
        )
        XCTAssertEqual(action, .beginMarquee(additive: true))
    }

    func testCommandWithoutArmIsIgnored() {
        let action = PressDragSelectLogic.startAction(
            hitID: "a",
            hitPath: "/tmp/a.pdf",
            hitIsSelected: false,
            selectedPaths: [],
            commandHeld: true,
            shiftHeld: false,
            hasArmedFileDrag: false,
            armedPaths: [],
            isArming: false
        )
        XCTAssertEqual(action, .ignore)
    }
}
