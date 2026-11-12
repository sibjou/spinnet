import XCTest
@testable import Spinnet

final class NotificationGroupingTests: XCTestCase {

    private let cal = TestCalendar.utc
    private func at(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        TestCalendar.date(2026, 10, day, hour, minute)
    }

    private func note(_ id: String, _ type: NotificationType, created: Date? = nil) -> AppNotification {
        AppNotification(id: id, data: [
            "type": type.rawValue, "title": "t", "body": "b", "createdAt": created ?? at(15)
        ])!
    }

    func testChatEventsAreHidden() {
        let items = [note("1", .requestBooked), note("2", .clarification), note("3", .matchProposed)]
        XCTAssertEqual(NotificationGrouping.visible(items).map(\.id), ["1", "3"])
    }

    func testEverythingElseStays() {
        let items = NotificationType.allCases.filter { $0 != .clarification }.enumerated().map { note("\($0.offset)", $0.element) }
        XCTAssertEqual(NotificationGrouping.visible(items).count, items.count)
    }

    func testDayTitles() {
        XCTAssertEqual(NotificationGrouping.dayTitle(for: at(15, 8), now: at(15, 20), calendar: cal), "Сегодня")
        XCTAssertEqual(NotificationGrouping.dayTitle(for: at(14, 23), now: at(15, 1), calendar: cal), "Вчера")
        XCTAssertFalse(NotificationGrouping.dayTitle(for: at(10), now: at(15), calendar: cal).isEmpty)
        XCTAssertNotEqual(NotificationGrouping.dayTitle(for: at(10), now: at(15), calendar: cal), "Сегодня")
    }

    func testOtherYearShowsYear() {
        let old = TestCalendar.date(2025, 3, 2, 12)
        let title = NotificationGrouping.dayTitle(for: old, now: at(15), calendar: cal)
        XCTAssertTrue(title.contains("2025"), title)
    }

    func testTimeAgo() {
        let now = at(15, 12)
        XCTAssertEqual(NotificationGrouping.timeAgo(now.addingTimeInterval(-20), now: now), "только что")
        XCTAssertEqual(NotificationGrouping.timeAgo(now.addingTimeInterval(-5 * 60), now: now), "5 мин назад")
        XCTAssertEqual(NotificationGrouping.timeAgo(now.addingTimeInterval(-3 * 3600), now: now), "3 ч назад")
        XCTAssertEqual(NotificationGrouping.timeAgo(now.addingTimeInterval(-2 * 86400), now: now), "2 дн назад")
        XCTAssertFalse(NotificationGrouping.timeAgo(now.addingTimeInterval(-30 * 86400), now: now).contains("назад"))
    }

    func testFutureTimestampDoesNotBreak() {
        let now = at(15, 12)
        XCTAssertEqual(NotificationGrouping.timeAgo(now.addingTimeInterval(120), now: now), "только что")
    }
}
