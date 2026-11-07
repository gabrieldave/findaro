import XCTest
@testable import OrdenCore

final class AssistantShortcutTests: XCTestCase {
    func testTodayWindow() {
        let cal = Calendar.current
        let now = Date()
        XCTAssertTrue(ShortcutDateWindow.today.matches(now, now: now, calendar: cal))
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        XCTAssertFalse(ShortcutDateWindow.today.matches(yesterday, now: now, calendar: cal))
    }

    func testLastDaysIncludesBoundary() {
        let cal = Calendar.current
        let now = Date()
        let threeAgo = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: now))!
        XCTAssertTrue(ShortcutDateWindow.lastDays(3).matches(threeAgo, now: now, calendar: cal))
        let fourAgo = cal.date(byAdding: .day, value: -4, to: now)!
        XCTAssertFalse(ShortcutDateWindow.lastDays(3).matches(fourAgo, now: now, calendar: cal))
    }

    func testInferImagesToday() {
        let s = AgentIntentParser.inferShortcut(from: "imágenes de hoy")
        XCTAssertEqual(s?.categories, [.image])
        XCTAssertEqual(s?.dateWindow, .today)
    }

    func testInferMusicThreeDays() {
        let s = AgentIntentParser.inferShortcut(from: "musica de hace 3 dias")
        XCTAssertEqual(s?.categories, [.audio])
        XCTAssertEqual(s?.dateWindow, .lastDays(3))
    }

    func testMaxCount() {
        XCTAssertEqual(AssistantShortcut.maxCount, 80)
        XCTAssertFalse(AssistantShortcut.factoryDefaults().isEmpty)
    }
}
