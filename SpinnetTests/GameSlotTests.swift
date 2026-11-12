import XCTest
@testable import Spinnet

final class GameSlotTests: XCTestCase {

    func testParsesSlotWithEnDash() {
        let range = GameSlot.minutes(from: "18:00 – 20:00")
        XCTAssertEqual(range?.start, 18 * 60)
        XCTAssertEqual(range?.end, 20 * 60)
        XCTAssertEqual(GameSlot.durationMinutes(of: "18:00 – 20:00"), 120)
    }

    func testParsesSlotWithHyphenAndShortHours() {
        XCTAssertEqual(GameSlot.durationMinutes(of: "9:30 - 11:00"), 90)
    }

    func testSlotPastMidnight() {
        XCTAssertEqual(GameSlot.durationMinutes(of: "22:00 – 00:00"), 120)
    }

    func testBrokenSlot() {
        XCTAssertNil(GameSlot.minutes(from: "вечером"))
        XCTAssertNil(GameSlot.minutes(from: "25:00 – 26:00"))
        XCTAssertEqual(GameSlot.durationMinutes(of: ""), 0)
    }

    func testStartDate() {
        let day = TestCalendar.date(2026, 10, 12, 0, 0)
        let start = GameSlot.startDate(day: day, slot: "18:30 – 20:00", calendar: TestCalendar.utc)
        XCTAssertEqual(start, TestCalendar.date(2026, 10, 12, 18, 30))
    }
}
