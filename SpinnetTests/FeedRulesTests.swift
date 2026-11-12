import XCTest
@testable import Spinnet

// Правила ленты: какой город показывать, какие дни и уровни подходят, что уже прошло.
// 15 октября 2026 — четверг; суббота — 17-е, воскресенье — 18-е.

final class FeedRulesTests: XCTestCase {

    private let cal = TestCalendar.utc
    private func at(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        TestCalendar.date(2026, 10, day, hour, minute)
    }

    // MARK: Город

    func testFeedFollowsProfileCityByDefault() {
        XCTAssertEqual(FeedCity.effective(home: "Томск", saved: nil), "Томск")
        XCTAssertEqual(FeedCity.effective(home: "томск ", saved: nil), "Томск")
    }

    func testFeedWithoutProfileCityShowsEverything() {
        XCTAssertEqual(FeedCity.effective(home: "", saved: nil), FeedCity.all)
        XCTAssertEqual(FeedCity.effective(home: "   ", saved: nil), FeedCity.all)
    }

    func testSavedChoiceBeatsProfile() {
        XCTAssertEqual(FeedCity.effective(home: "Томск", saved: "Новосибирск"), "Новосибирск")
        XCTAssertEqual(FeedCity.effective(home: "Томск", saved: FeedCity.all), FeedCity.all)
        XCTAssertEqual(FeedCity.effective(home: "", saved: "Омск"), "Омск")
    }

    func testEmptySavedChoiceIsIgnored() {
        XCTAssertEqual(FeedCity.effective(home: "Томск", saved: ""), "Томск")
    }

    func testChoosingHomeCityStoresNothing() {
        // После выбора своего города лента снова следует за профилем: сменил город в профиле — лента перешла
        XCTAssertNil(FeedCity.savedValue(chosen: "Томск", home: "Томск"))
        XCTAssertNil(FeedCity.savedValue(chosen: "томск", home: "Томск "))
    }

    func testChoosingOtherCityIsStored() {
        XCTAssertEqual(FeedCity.savedValue(chosen: "Новосибирск", home: "Томск"), "Новосибирск")
        XCTAssertEqual(FeedCity.savedValue(chosen: "Омск", home: ""), "Омск")
    }

    func testChoosingAllCitiesIsStored() {
        XCTAssertEqual(FeedCity.savedValue(chosen: FeedCity.all, home: "Томск"), FeedCity.all)
        XCTAssertEqual(FeedCity.savedValue(chosen: FeedCity.all, home: ""), FeedCity.all)
    }

    func testStorageKeyIsPerAccount() {
        XCTAssertNotEqual(FeedCity.storageKey(userId: "a"), FeedCity.storageKey(userId: "b"))
    }

    // MARK: День

    func testAnyDayMatchesEverything() {
        XCTAssertTrue(FeedDay.any.matches(at(1), now: at(15), calendar: cal))
        XCTAssertTrue(FeedDay.any.matches(at(30), now: at(15), calendar: cal))
    }

    func testToday() {
        XCTAssertTrue(FeedDay.today.matches(at(15, 0, 0), now: at(15, 23, 59), calendar: cal))
        XCTAssertFalse(FeedDay.today.matches(at(16), now: at(15), calendar: cal))
        XCTAssertFalse(FeedDay.today.matches(at(14), now: at(15), calendar: cal))
    }

    func testTomorrow() {
        XCTAssertTrue(FeedDay.tomorrow.matches(at(16, 8), now: at(15, 22), calendar: cal))
        XCTAssertFalse(FeedDay.tomorrow.matches(at(15), now: at(15), calendar: cal))
        XCTAssertFalse(FeedDay.tomorrow.matches(at(17), now: at(15), calendar: cal))
    }

    func testTomorrowAcrossMonthEnd() {
        let now = TestCalendar.date(2026, 10, 31, 20)
        XCTAssertTrue(FeedDay.tomorrow.matches(TestCalendar.date(2026, 11, 1, 9), now: now, calendar: cal))
    }

    func testWeekendIsSaturdayAndSunday() {
        XCTAssertFalse(FeedDay.weekend.matches(at(16), now: at(15), calendar: cal))   // пятница
        XCTAssertTrue(FeedDay.weekend.matches(at(17), now: at(15), calendar: cal))    // суббота
        XCTAssertTrue(FeedDay.weekend.matches(at(18), now: at(15), calendar: cal))    // воскресенье
        XCTAssertFalse(FeedDay.weekend.matches(at(19), now: at(15), calendar: cal))   // понедельник
    }

    func testWeekendTodayCountsWhenItIsWeekend() {
        XCTAssertTrue(FeedDay.weekend.matches(at(17), now: at(17), calendar: cal))
    }

    func testDayTitlesAreDistinct() {
        let titles = FeedDay.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertEqual(FeedDay.allCases.first, .any)
    }

    // MARK: Что ещё не прошло

    func testGameInFutureIsUpcoming() {
        XCTAssertTrue(RequestTiming.isUpcoming(day: at(15, 0), slot: "18:00 – 20:00", now: at(15, 10), calendar: cal))
    }

    func testGameInProgressIsStillUpcoming() {
        // Игра началась, но не закончилась: к ней ещё можно присоединиться
        XCTAssertTrue(RequestTiming.isUpcoming(day: at(15, 0), slot: "18:00 – 20:00", now: at(15, 19), calendar: cal))
    }

    func testFinishedGameIsNotUpcoming() {
        XCTAssertFalse(RequestTiming.isUpcoming(day: at(15, 0), slot: "18:00 – 20:00", now: at(15, 20, 0), calendar: cal))
        XCTAssertFalse(RequestTiming.isUpcoming(day: at(14, 0), slot: "18:00 – 20:00", now: at(15, 1), calendar: cal))
    }

    func testPastMidnightGameLivesUntilItEnds() {
        XCTAssertTrue(RequestTiming.isUpcoming(day: at(15, 0), slot: "22:00 – 01:00", now: at(16, 0, 30), calendar: cal))
        XCTAssertFalse(RequestTiming.isUpcoming(day: at(15, 0), slot: "22:00 – 01:00", now: at(16, 1, 0), calendar: cal))
    }

    func testUnreadableSlotLivesUntilEndOfDay() {
        XCTAssertTrue(RequestTiming.isUpcoming(day: at(15, 0), slot: "вечером", now: at(15, 23, 30), calendar: cal))
        XCTAssertFalse(RequestTiming.isUpcoming(day: at(15, 0), slot: "вечером", now: at(16, 0, 0), calendar: cal))
        XCTAssertTrue(RequestTiming.isUpcoming(day: at(15, 0), slot: "", now: at(15, 8), calendar: cal))
    }

    func testSortKeyOrdersByStartTime() {
        let early = RequestTiming.sortKey(day: at(15, 0), slot: "09:00 – 10:00", calendar: cal)
        let late = RequestTiming.sortKey(day: at(15, 0), slot: "19:00 – 21:00", calendar: cal)
        let nextDay = RequestTiming.sortKey(day: at(16, 0), slot: "08:00 – 09:00", calendar: cal)
        XCTAssertLessThan(early, late)
        XCTAssertLessThan(late, nextDay)
        XCTAssertEqual(early, at(15, 9, 0))
    }

    func testSortKeyWithBrokenSlotIsStartOfDay() {
        let key = RequestTiming.sortKey(day: at(15, 13), slot: "когда-нибудь", calendar: cal)
        XCTAssertEqual(key, at(15, 0, 0))
    }

    // MARK: Уровень

    func testSameLevelFits() {
        XCTAssertTrue(LevelMatch.fits(myLevel: "Любитель", authorLevel: "Любитель", desiredLevel: "Любой"))
    }

    func testNeighbourLevelFits() {
        XCTAssertTrue(LevelMatch.fits(myLevel: "Любитель", authorLevel: "Начинающий", desiredLevel: "Любой"))
        XCTAssertTrue(LevelMatch.fits(myLevel: "Любитель", authorLevel: "Продвинутый", desiredLevel: "Любой"))
    }

    func testFarLevelDoesNotFit() {
        XCTAssertFalse(LevelMatch.fits(myLevel: "Начинающий", authorLevel: "Продвинутый", desiredLevel: "Любой"))
        XCTAssertFalse(LevelMatch.fits(myLevel: "Профессионал", authorLevel: "Любитель", desiredLevel: "Любой"))
    }

    func testAuthorWantsDifferentLevel() {
        XCTAssertFalse(LevelMatch.fits(myLevel: "Любитель", authorLevel: "Любитель", desiredLevel: "Продвинутый"))
        XCTAssertTrue(LevelMatch.fits(myLevel: "Продвинутый", authorLevel: "Любитель", desiredLevel: "Продвинутый"))
    }

    func testUnknownMyLevelFiltersNothing() {
        XCTAssertTrue(LevelMatch.fits(myLevel: "", authorLevel: "Профессионал", desiredLevel: "Начинающий"))
    }

    func testUnknownAuthorLevelIsNotAReasonToHide() {
        XCTAssertTrue(LevelMatch.fits(myLevel: "Любитель", authorLevel: "", desiredLevel: "Любой"))
    }

    func testBars() {
        XCTAssertEqual(LevelMatch.bars("Начинающий"), 1)
        XCTAssertEqual(LevelMatch.bars("Любитель"), 2)
        XCTAssertEqual(LevelMatch.bars("Продвинутый"), 3)
        XCTAssertEqual(LevelMatch.bars("Профессионал"), 4)
        XCTAssertEqual(LevelMatch.bars("Любой"), 0)
        XCTAssertEqual(LevelMatch.bars(""), 0)
    }
}

// MARK: - Порядок и подписи

final class FeedOrderTests: XCTestCase {

    private let cal = TestCalendar.utc
    private func at(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        TestCalendar.date(2026, 10, day, hour, minute)
    }

    private struct Item: Equatable {
        let name: String
        let day: Date
        let slot: String
        let created: Date
    }

    private func order(_ items: [Item]) -> [String] {
        FeedOrder.sorted(items, day: \.day, slot: \.slot, createdAt: \.created, calendar: cal).map(\.name)
    }

    func testNearestGameFirst() {
        let items = [
            Item(name: "послезавтра", day: at(17, 0), slot: "10:00 – 12:00", created: at(1)),
            Item(name: "вечером", day: at(15, 0), slot: "19:00 – 21:00", created: at(2)),
            Item(name: "утром", day: at(15, 0), slot: "09:00 – 10:00", created: at(3)),
            Item(name: "завтра", day: at(16, 0), slot: "08:00 – 09:00", created: at(4))
        ]
        XCTAssertEqual(order(items), ["утром", "вечером", "завтра", "послезавтра"])
    }

    func testSameStartNewestRequestFirst() {
        let items = [
            Item(name: "старая", day: at(15, 0), slot: "18:00 – 20:00", created: at(1)),
            Item(name: "новая", day: at(15, 0), slot: "18:00 – 20:00", created: at(10))
        ]
        XCTAssertEqual(order(items), ["новая", "старая"])
    }

    func testBrokenSlotGoesToStartOfItsDay() {
        let items = [
            Item(name: "с временем", day: at(15, 0), slot: "08:00 – 09:00", created: at(1)),
            Item(name: "без времени", day: at(15, 0), slot: "вечером", created: at(2)),
            Item(name: "завтра", day: at(16, 0), slot: "07:00 – 08:00", created: at(3))
        ]
        XCTAssertEqual(order(items), ["без времени", "с временем", "завтра"])
    }

    func testEmptyAndSingle() {
        XCTAssertEqual(order([]), [])
        XCTAssertEqual(order([Item(name: "одна", day: at(15, 0), slot: "10:00 – 11:00", created: at(1))]), ["одна"])
    }

    func testInProgress() {
        XCTAssertTrue(RequestTiming.isInProgress(day: at(15, 0), slot: "18:00 – 20:00", now: at(15, 18, 0), calendar: cal))
        XCTAssertTrue(RequestTiming.isInProgress(day: at(15, 0), slot: "18:00 – 20:00", now: at(15, 19, 59), calendar: cal))
        XCTAssertFalse(RequestTiming.isInProgress(day: at(15, 0), slot: "18:00 – 20:00", now: at(15, 17, 59), calendar: cal))
        XCTAssertFalse(RequestTiming.isInProgress(day: at(15, 0), slot: "18:00 – 20:00", now: at(15, 20, 0), calendar: cal))
        XCTAssertFalse(RequestTiming.isInProgress(day: at(15, 0), slot: "вечером", now: at(15, 19), calendar: cal))
    }

    func testInProgressAfterMidnight() {
        XCTAssertTrue(RequestTiming.isInProgress(day: at(15, 0), slot: "23:00 – 01:00", now: at(16, 0, 30), calendar: cal))
    }

    func testDayWord() {
        XCTAssertEqual(RequestTiming.dayWord(for: at(15, 9), now: at(15, 20), calendar: cal), "Сегодня")
        XCTAssertEqual(RequestTiming.dayWord(for: at(16, 9), now: at(15, 20), calendar: cal), "Завтра")
        XCTAssertNil(RequestTiming.dayWord(for: at(17, 9), now: at(15, 20), calendar: cal))
        XCTAssertNil(RequestTiming.dayWord(for: at(14, 9), now: at(15, 20), calendar: cal))
    }
}

final class FeedGroupingTests: XCTestCase {

    private let cal = TestCalendar.utc
    private func at(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        TestCalendar.date(2026, 10, day, hour, minute)
    }

    func testGroupsConsecutiveItemsOfOneDay() {
        let days = [at(15, 9), at(15, 19), at(16, 8), at(17, 10), at(17, 18)]
        let sections = FeedGrouping.sections(days, day: { $0 }, calendar: cal)
        XCTAssertEqual(sections.map { $0.items.count }, [2, 1, 2])
        XCTAssertEqual(sections.map(\.day), [at(15, 0), at(16, 0), at(17, 0)])
    }

    func testKeepsOrderInsideSections() {
        let days = [at(15, 9), at(15, 11), at(15, 19)]
        let sections = FeedGrouping.sections(days, day: { $0 }, calendar: cal)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].items, days)
    }

    func testEmptyList() {
        XCTAssertTrue(FeedGrouping.sections([Date](), day: { $0 }, calendar: cal).isEmpty)
    }

    func testSectionIdsAreDistinct() {
        let sections = FeedGrouping.sections([at(15), at(16), at(17)], day: { $0 }, calendar: cal)
        XCTAssertEqual(Set(sections.map(\.id)).count, 3)
    }

    func testTitleForTodayAndTomorrowStartsWithWord() {
        XCTAssertTrue(FeedGrouping.title(for: at(15, 9), now: at(15, 20), calendar: cal).hasPrefix("Сегодня, "))
        XCTAssertTrue(FeedGrouping.title(for: at(16, 9), now: at(15, 20), calendar: cal).hasPrefix("Завтра, "))
    }

    func testTitleForOtherDayStartsWithCapital() {
        let title = FeedGrouping.title(for: at(17, 9), now: at(15, 20), calendar: cal)
        XCTAssertFalse(title.isEmpty)
        XCTAssertEqual(String(title.prefix(1)), title.prefix(1).uppercased())
    }
}
