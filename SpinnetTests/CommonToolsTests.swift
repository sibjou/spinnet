import XCTest
@testable import Spinnet

// MARK: - Время по умолчанию в форме заявки

final class MeetingDefaultsTests: XCTestCase {

    private let cal = TestCalendar.utc

    private func slot(at hour: Int, _ minute: Int = 0) -> MeetingDefaults.Slot {
        MeetingDefaults.initialSlot(now: TestCalendar.date(2026, 10, 13, hour, minute), calendar: cal)
    }

    private func minutes(_ date: Date) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    func testDaytimeDefaultsToTodayStartingInAnHourRoundedUp() {
        let result = slot(at: 14, 10)          // через час 15:10 → 15:30
        XCTAssertTrue(cal.isDate(result.day, inSameDayAs: TestCalendar.date(2026, 10, 13)))
        XCTAssertEqual(minutes(result.start), 15 * 60 + 30)
        XCTAssertEqual(minutes(result.end), 17 * 60 + 30)
    }

    func testExactHalfHourIsKept() {
        XCTAssertEqual(minutes(slot(at: 10, 30).start), 11 * 60 + 30)
    }

    func testEarlyMorningStartsLaterTheSameDay() {
        let result = slot(at: 0, 5)
        XCTAssertTrue(cal.isDate(result.day, inSameDayAs: TestCalendar.date(2026, 10, 13)))
        XCTAssertEqual(minutes(result.start), 1 * 60 + 30)
    }

    func testLateEveningMovesToTomorrowEvening() {
        let result = slot(at: 21, 0)           // через час 22:00 — уже поздно
        XCTAssertTrue(cal.isDate(result.day, inSameDayAs: TestCalendar.date(2026, 10, 14)))
        XCTAssertEqual(minutes(result.start), 18 * 60)
        XCTAssertEqual(minutes(result.end), 20 * 60)
    }

    func testLastAllowedStartIsHalfPastNine() {
        let result = slot(at: 20, 25)          // 21:25 → 21:30, ещё сегодня
        XCTAssertTrue(cal.isDate(result.day, inSameDayAs: TestCalendar.date(2026, 10, 13)))
        XCTAssertEqual(minutes(result.start), 21 * 60 + 30)
        XCTAssertEqual(minutes(result.end), 23 * 60 + 30)
    }

    func testAfterMidnightRolloverGoesToTomorrow() {
        let result = slot(at: 23, 40)
        XCTAssertTrue(cal.isDate(result.day, inSameDayAs: TestCalendar.date(2026, 10, 14)))
    }

    func testEndIsAlwaysAfterStart() {
        for hour in 0..<24 {
            let result = slot(at: hour, 45)
            XCTAssertGreaterThan(result.end, result.start, "час \(hour)")
        }
    }

    func testCombineTakesDayFromOneAndClockFromOther() {
        let day = TestCalendar.date(2026, 10, 20, 3, 0)
        let time = TestCalendar.date(2001, 1, 1, 18, 45)
        let result = MeetingDefaults.combine(day: day, time: time, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day, .hour, .minute], from: result),
                       DateComponents(year: 2026, month: 10, day: 20, hour: 18, minute: 45))
    }

    func testStartInPastDetection() {
        let today = TestCalendar.date(2026, 10, 13, 0, 0)
        let now = TestCalendar.date(2026, 10, 13, 15, 0)
        XCTAssertTrue(MeetingDefaults.startsInPast(day: today, start: TestCalendar.date(2001, 1, 1, 12, 0), now: now, calendar: cal))
        XCTAssertFalse(MeetingDefaults.startsInPast(day: today, start: TestCalendar.date(2001, 1, 1, 18, 0), now: now, calendar: cal))
        let tomorrow = TestCalendar.date(2026, 10, 14, 0, 0)
        XCTAssertFalse(MeetingDefaults.startsInPast(day: tomorrow, start: TestCalendar.date(2001, 1, 1, 9, 0), now: now, calendar: cal))
    }

    func testStartAtThisMinuteIsNotPast() {
        let today = TestCalendar.date(2026, 10, 13, 0, 0)
        let now = TestCalendar.date(2026, 10, 13, 15, 0)
        XCTAssertFalse(MeetingDefaults.startsInPast(day: today, start: TestCalendar.date(2001, 1, 1, 15, 0), now: now, calendar: cal))
    }
}

// MARK: - Даты на языке приложения

final class AppDateTests: XCTestCase {

    private let sample = TestCalendar.date(2026, 10, 13, 18, 30)

    func testClockIsTwentyFourHourAndParsesBack() {
        let timezoneIndependent = AppDate.parseClock("18:30")
        XCTAssertNotNil(timezoneIndependent)
        XCTAssertEqual(AppDate.clock(timezoneIndependent ?? Date()), "18:30")
        XCTAssertNil(AppDate.parseClock("25:99"))
        XCTAssertNil(AppDate.parseClock("вечером"))
    }

    func testFormattedDatesContainTheDayNumber() {
        // Даты на экране показываются в часовом поясе телефона. 18:30 по UTC в Томске (UTC+7) — уже 14 октября,
        // поэтому ожидаемый день считаем в том же часовом поясе, а не по UTC
        let day = Calendar.current.component(.day, from: sample)
        for text in [AppDate.dayShort(sample), AppDate.dayLong(sample), AppDate.dayLongYear(sample),
                     AppDate.fullWithWeekday(sample), AppDate.shortWithWeekday(sample)] {
            XCTAssertFalse(text.isEmpty)
            XCTAssertTrue(text.contains("\(day)"), text)
        }
    }

    #if canImport(Darwin)
    func testLanguageIsRussianByDefaultNotEnglish() {
        XCTAssertTrue(AppLocale.current.identifier.hasPrefix("ru"))
    }

    func testMonthNamesAreRussian() {
        let text = AppDate.dayLong(sample)
        XCTAssertTrue(text.contains("октября"), text)
        XCTAssertFalse(text.contains("Oct"), text)
    }
    #endif
}

// MARK: - Понятные ошибки

final class UserFacingErrorTests: XCTestCase {

    func testNoInternet() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertTrue(UserFacingError.message(for: error, fallback: "x").contains("интернет"))
    }

    func testFirestoreUnavailableAndPermissionDenied() {
        let unavailable = NSError(domain: UserFacingError.firestoreDomain, code: 14)
        let denied = NSError(domain: UserFacingError.firestoreDomain, code: 7)
        XCTAssertTrue(UserFacingError.message(for: unavailable, fallback: "x").contains("сервер"))
        XCTAssertTrue(UserFacingError.message(for: denied, fallback: "x").contains("прав"))
    }

    func testUnknownErrorUsesOurFallbackNotTheEnglishSystemText() {
        let error = NSError(domain: "SomeEnglishDomain", code: 99,
                            userInfo: [NSLocalizedDescriptionKey: "The operation couldn't be completed."])
        XCTAssertEqual(UserFacingError.message(for: error, fallback: "Не удалось сохранить"), "Не удалось сохранить")
    }
}
