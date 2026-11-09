import XCTest
@testable import OrdenCore

final class ClickModifierMemoryTests: XCTestCase {
    func testCommandHeldAtMouseDownSurvivesEarlyRelease() {
        var memory = ClickModifierMemory()
        memory.recordMouseDown(.init(command: true), at: 100)
        // El usuario ya soltó ⌘ cuando SwiftUI dispara el clic simple (0,4 s después).
        let resolved = memory.resolve(now: 100.4, current: .none)
        XCTAssertTrue(resolved.command)
        XCTAssertFalse(resolved.shift)
    }

    func testShiftHeldAtMouseDownSurvivesEarlyRelease() {
        var memory = ClickModifierMemory()
        memory.recordMouseDown(.init(shift: true), at: 50)
        XCTAssertTrue(memory.resolve(now: 50.3, current: .none).shift)
    }

    func testStaleCaptureIsIgnored() {
        var memory = ClickModifierMemory()
        memory.recordMouseDown(.init(command: true), at: 10)
        XCTAssertFalse(memory.resolve(now: 20, current: .none).command)
    }

    func testPlainClickStaysPlain() {
        var memory = ClickModifierMemory()
        memory.recordMouseDown(.none, at: 5)
        XCTAssertEqual(memory.resolve(now: 5.2, current: .none), .none)
    }

    func testCurrentlyHeldKeyStillCounts() {
        let memory = ClickModifierMemory()
        XCTAssertTrue(memory.resolve(now: 1, current: .init(command: true)).command)
    }

    /// Mouse con "velocidad de doble clic" lenta (p. ej. 3 s): el clic simple llega tarde
    /// pero debe conservar ⌘ capturado en el mouseDown.
    func testSlowMouseDoubleClickSettingKeepsModifier() {
        var memory = ClickModifierMemory()
        memory.recordMouseDown(.init(command: true), at: 200)
        let window = ClickModifierMemory.window(doubleClickInterval: 3.0)
        XCTAssertTrue(memory.resolve(now: 203.2, current: .none, window: window).command)
        XCTAssertFalse(memory.resolve(now: 203.2, current: .none).command, "Con la ventana fija de 1,5 s fallaba")
    }

    func testWindowNeverShorterThanMinimum() {
        XCTAssertEqual(ClickModifierMemory.window(doubleClickInterval: 0.2), ClickModifierMemory.maxAge)
    }
}
