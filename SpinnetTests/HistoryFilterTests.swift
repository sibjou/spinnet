import XCTest
@testable import Spinnet

// MARK: - Вспомогательные данные

private var cal: Calendar { TestCalendar.utc }
private var now: Date { TestCalendar.date(2026, 10, 13, 15) }

private func game(_ id: String,
                  _ date: Date,
                  name: String = "Иван Петров",
                  city: String = "Томск",
                  place: String = "ТПУ",
                  role: HistoryGame.Role = .author,
                  held: Bool = true,
                  won: Int = 0,
                  lost: Int = 0) -> HistoryGame {
    HistoryGame(id: id, date: date, role: role, partnerId: "p-\(name)", partnerName: name,
                city: city, place: place, wasHeld: held, matchesWon: won, matchesLost: lost)
}

private func match(_ id: String, _ date: Date, opponent: String = "Иван", won: Bool = true, ordinal: Int = 1) -> HistoryMatch {
    HistoryMatch(id: id, date: date, opponentId: "o-\(opponent)", opponentName: opponent, won: won,
                 gamesWon: won ? 3 : 1, gamesLost: won ? 1 : 3, ordinal: ordinal)
}

private struct FakeReview: RatedReview {
    let rating: Int
    let comment: String
    let createdAt: Date
}

// MARK: - Период

final class HistoryPeriodTests: XCTestCase {

    func testAllTimeContainsEverything() {
        XCTAssertTrue(HistoryPeriod.allTime.contains(TestCalendar.date(2020, 1, 1), now: now, calendar: cal))
    }

    func testLast7DaysCountsTodayAsOneOfSeven() {
        let period = HistoryPeriod.last7Days
        XCTAssertTrue(period.contains(TestCalendar.date(2026, 10, 7, 0, 5), now: now, calendar: cal))   // 7 октября — первый день
        XCTAssertFalse(period.contains(TestCalendar.date(2026, 10, 6, 23, 59), now: now, calendar: cal))
    }

    func testLast30And90Days() {
        XCTAssertTrue(HistoryPeriod.last30Days.contains(TestCalendar.date(2026, 9, 14), now: now, calendar: cal))
        XCTAssertFalse(HistoryPeriod.last30Days.contains(TestCalendar.date(2026, 9, 13), now: now, calendar: cal))
        XCTAssertTrue(HistoryPeriod.last90Days.contains(TestCalendar.date(2026, 7, 16), now: now, calendar: cal))
        XCTAssertFalse(HistoryPeriod.last90Days.contains(TestCalendar.date(2026, 7, 14), now: now, calendar: cal))
    }

    func testThisYear() {
        XCTAssertTrue(HistoryPeriod.thisYear.contains(TestCalendar.date(2026, 1, 1), now: now, calendar: cal))
        XCTAssertFalse(HistoryPeriod.thisYear.contains(TestCalendar.date(2025, 12, 31), now: now, calendar: cal))
    }

    func testSpecificMonth() {
        let period = HistoryPeriod.month(YearMonth(year: 2026, month: 9))
        XCTAssertTrue(period.contains(TestCalendar.date(2026, 9, 30, 23), now: now, calendar: cal))
        XCTAssertFalse(period.contains(TestCalendar.date(2026, 10, 1, 0, 1), now: now, calendar: cal))
        XCTAssertFalse(period.contains(TestCalendar.date(2025, 9, 15), now: now, calendar: cal))
    }

    func testMonthsAreListedNewestFirstWithCounts() {
        let dates = [TestCalendar.date(2026, 8, 3), TestCalendar.date(2026, 10, 1),
                     TestCalendar.date(2026, 10, 9), TestCalendar.date(2025, 12, 31)]
        let buckets = HistoryBuckets.months(of: dates, calendar: cal)
        XCTAssertEqual(buckets.map { $0.month }, [YearMonth(year: 2026, month: 10),
                                                  YearMonth(year: 2026, month: 8),
                                                  YearMonth(year: 2025, month: 12)])
        XCTAssertEqual(buckets.map { $0.count }, [2, 1, 1])
    }

    func testGroupingKeepsOrderAndSplitsByMonth() {
        let items = [TestCalendar.date(2026, 10, 9), TestCalendar.date(2026, 10, 1), TestCalendar.date(2026, 9, 20)]
        let groups = HistoryBuckets.groupedByMonth(items, date: { $0 }, calendar: cal)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].items.count, 2)
        XCTAssertEqual(groups[1].month, YearMonth(year: 2026, month: 9))
    }

    func testYearMonthOrdering() {
        XCTAssertTrue(YearMonth(year: 2025, month: 12) < YearMonth(year: 2026, month: 1))
        XCTAssertTrue(YearMonth(year: 2026, month: 2) < YearMonth(year: 2026, month: 11))
    }
}

// MARK: - Игры

final class GameHistoryFilterTests: XCTestCase {

    private var games: [HistoryGame] {
        [
            game("g1", TestCalendar.date(2026, 10, 10), name: "Иван Петров", city: "Томск", role: .author, won: 2, lost: 1),
            game("g2", TestCalendar.date(2026, 10, 2), name: "Анна Смирнова", city: "Томск", role: .partner, won: 0, lost: 2),
            game("g3", TestCalendar.date(2026, 9, 20), name: "Борис Орлов", city: "Новосибирск", place: "Академгородок", role: .partner),
            game("g4", TestCalendar.date(2026, 9, 5), name: "Иван Петров", city: "Томск", role: .author, held: false),
            game("g5", TestCalendar.date(2025, 6, 1), name: "Елена Ким", city: "Кемерово", role: .author, won: 1, lost: 1)
        ]
    }

    func testDefaultFilterKeepsAllAndSortsNewestFirst() {
        let filter = GameHistoryFilter()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g1", "g2", "g3", "g4", "g5"])
    }

    func testOldestFirst() {
        var filter = GameHistoryFilter()
        filter.sort = .oldestFirst
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g5", "g4", "g3", "g2", "g1"])
    }

    func testSortByOpponentThenNewest() {
        var filter = GameHistoryFilter()
        filter.sort = .byOpponent
        // Анна, Борис, Елена, Иван (новая), Иван (старая)
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g2", "g3", "g5", "g1", "g4"])
    }

    func testPeriodFilter() {
        var filter = GameHistoryFilter()
        filter.period = .last30Days
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g1", "g2", "g3"])
        filter.period = .month(YearMonth(year: 2026, month: 9))
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g3", "g4"])
    }

    func testRoleFilter() {
        var filter = GameHistoryFilter()
        filter.role = .created
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g1", "g4", "g5"])
        filter.role = .joined
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g2", "g3"])
    }

    func testOutcomeFilters() {
        var filter = GameHistoryFilter()
        filter.outcome = .won
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g1"])
        filter.outcome = .lost
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g2"])
        filter.outcome = .noScore
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g3"])
        filter.outcome = .notHeld
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g4"])
    }

    func testEvenRecordIsNeitherWinNorLoss() {
        var filter = GameHistoryFilter()
        filter.outcome = .won
        XCTAssertFalse(filter.apply(to: games, now: now, calendar: cal).contains { $0.id == "g5" })
        filter.outcome = .lost
        XCTAssertFalse(filter.apply(to: games, now: now, calendar: cal).contains { $0.id == "g5" })
    }

    func testCityFilterAndCityList() {
        var filter = GameHistoryFilter()
        filter.city = "Новосибирск"
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g3"])
        XCTAssertEqual(GameHistoryFilter.cities(in: games), ["Томск", "Кемерово", "Новосибирск"])
    }

    /// Тот самый случай со скриншота: «Мурманск» дважды, «Санкт-Петербург» дважды и «Мурманска»
    func testSameCityWrittenDifferentlyIsOneMenuItem() {
        let mixed = [
            game("m1", TestCalendar.date(2026, 10, 10), city: "Мурманск"),
            game("m2", TestCalendar.date(2026, 10, 9),  city: "Мурманск "),             // пробел в конце
            game("m3", TestCalendar.date(2026, 10, 8),  city: "мурманск"),
            game("m4", TestCalendar.date(2026, 10, 7),  city: "Мурманска"),
            game("m5", TestCalendar.date(2026, 10, 6),  city: "МУРМАНСК"),
            game("m6", TestCalendar.date(2026, 10, 5),  city: "\u{4D}урманск"),        // «M» латинская
            game("s1", TestCalendar.date(2026, 10, 4),  city: "Санкт-Петербург"),
            game("s2", TestCalendar.date(2026, 10, 3),  city: "Санкт\u{2011}Петербург"), // неразрывный дефис
            game("s3", TestCalendar.date(2026, 10, 2),  city: "Санкт-Петербург\u{00A0}"),
            game("t1", TestCalendar.date(2026, 10, 1),  city: "Томск")
        ]
        XCTAssertEqual(GameHistoryFilter.cities(in: mixed), ["Мурманск", "Санкт-Петербург", "Томск"])

        // Выбрав «Мурманск», видим игры со всеми написаниями
        var filter = GameHistoryFilter()
        filter.city = "Мурманск"
        XCTAssertEqual(Set(filter.apply(to: mixed, now: now, calendar: cal).map { $0.id }),
                       ["m1", "m2", "m3", "m4", "m5", "m6"])
        filter.city = "Санкт-Петербург"
        XCTAssertEqual(Set(filter.apply(to: mixed, now: now, calendar: cal).map { $0.id }), ["s1", "s2", "s3"])
    }

    func testMenuNameIsTheMostCommonSpellingForUnknownCities() {
        let unknown = [
            game("a", TestCalendar.date(2026, 10, 3), city: "Заполярный"),
            game("b", TestCalendar.date(2026, 10, 2), city: "заполярный"),
            game("c", TestCalendar.date(2026, 10, 1), city: "ЗАПОЛЯРНЫЙ ")
        ]
        // Все три — один город; «Заполярный» встречается дважды, «ЗАПОЛЯРНЫЙ» — один раз
        XCTAssertEqual(GameHistoryFilter.cities(in: unknown), ["Заполярный"])
    }

    func testGamesWithoutCityAreNotInTheMenu() {
        let noCity = [game("x", TestCalendar.date(2026, 10, 1), city: ""),
                      game("y", TestCalendar.date(2026, 10, 2), city: "  ")]
        XCTAssertTrue(GameHistoryFilter.cities(in: noCity).isEmpty)
    }

    func testSearchFindsCityWrittenWithEnding() {
        var filter = GameHistoryFilter()
        filter.query = "мурманск"
        let found = filter.apply(to: [game("m4", TestCalendar.date(2026, 10, 7), city: "Мурманска")], now: now, calendar: cal)
        XCTAssertEqual(found.map { $0.id }, ["m4"])
    }

    func testSearchByNameCityAndPlaceIgnoringCase() {
        var filter = GameHistoryFilter()
        filter.query = "иван"
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g1", "g4"])
        filter.query = "  академ "
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g3"])
        filter.query = "кемер"
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g5"])
    }

    func testFiltersCombine() {
        var filter = GameHistoryFilter()
        filter.role = .created
        filter.period = .thisYear
        filter.query = "петров"
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).map { $0.id }, ["g1", "g4"])
        XCTAssertEqual(filter.activeCount, 3)
    }

    func testResetKeepsSort() {
        var filter = GameHistoryFilter()
        filter.role = .joined
        filter.query = "анна"
        filter.sort = .byOpponent
        filter.reset()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.sort, .byOpponent)
    }

    func testBlankQueryIsNotAFilter() {
        var filter = GameHistoryFilter()
        filter.query = "   "
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.apply(to: games, now: now, calendar: cal).count, 5)
    }

    func testOutcomeCounts() {
        XCTAssertEqual(GameHistoryFilter.count(of: .won, in: games), 1)
        XCTAssertEqual(GameHistoryFilter.count(of: .any, in: games), 5)
        XCTAssertEqual(GameHistoryFilter.count(of: .notHeld, in: games), 1)
    }
}

// MARK: - Матчи

final class MatchHistoryFilterTests: XCTestCase {

    private var matches: [HistoryMatch] {
        [
            match("m1", TestCalendar.date(2026, 10, 10), opponent: "Иван", won: true),
            match("m2", TestCalendar.date(2026, 10, 10), opponent: "Иван", won: false, ordinal: 2),
            match("m3", TestCalendar.date(2026, 9, 1), opponent: "Анна", won: false),
            match("m4", TestCalendar.date(2025, 3, 1), opponent: "Борис", won: true)
        ]
    }

    func testDefaultOrderNewestFirstAndLaterMatchOfSameDayOnTop() {
        let ids = MatchHistoryFilter().apply(to: matches, now: now, calendar: cal).map { $0.id }
        XCTAssertEqual(ids, ["m2", "m1", "m3", "m4"])
    }

    func testResultFilter() {
        var filter = MatchHistoryFilter()
        filter.result = .won
        XCTAssertEqual(filter.apply(to: matches, now: now, calendar: cal).map { $0.id }, ["m1", "m4"])
        filter.result = .lost
        XCTAssertEqual(filter.apply(to: matches, now: now, calendar: cal).map { $0.id }, ["m2", "m3"])
    }

    func testPeriodAndQuery() {
        var filter = MatchHistoryFilter()
        filter.period = .thisYear
        filter.query = "ив"
        XCTAssertEqual(filter.apply(to: matches, now: now, calendar: cal).map { $0.id }, ["m2", "m1"])
        XCTAssertEqual(filter.activeCount, 2)
    }

    func testSortByOpponent() {
        var filter = MatchHistoryFilter()
        filter.sort = .byOpponent
        XCTAssertEqual(filter.apply(to: matches, now: now, calendar: cal).map { $0.id }, ["m3", "m4", "m2", "m1"])
    }

    func testOldestFirst() {
        var filter = MatchHistoryFilter()
        filter.sort = .oldestFirst
        XCTAssertEqual(filter.apply(to: matches, now: now, calendar: cal).map { $0.id }, ["m4", "m3", "m1", "m2"])
    }

    func testResultCounts() {
        XCTAssertEqual(MatchHistoryFilter.count(of: .won, in: matches), 2)
        XCTAssertEqual(MatchHistoryFilter.count(of: .lost, in: matches), 2)
    }
}

// MARK: - Отзывы

final class ReviewFilterTests: XCTestCase {

    private var reviews: [FakeReview] {
        [
            FakeReview(rating: 5, comment: "Отличная игра", createdAt: TestCalendar.date(2026, 10, 1)),
            FakeReview(rating: 3, comment: "", createdAt: TestCalendar.date(2026, 10, 5)),
            FakeReview(rating: 5, comment: "   ", createdAt: TestCalendar.date(2026, 9, 1)),
            FakeReview(rating: 1, comment: "Опоздал", createdAt: TestCalendar.date(2026, 8, 1)),
            FakeReview(rating: 4, comment: "Хороший партнёр", createdAt: TestCalendar.date(2026, 10, 9))
        ]
    }

    func testNewestFirstByDefault() {
        let dates = ReviewFilter().apply(to: reviews).map { $0.createdAt }
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    func testOldestFirst() {
        var filter = ReviewFilter()
        filter.sort = .oldest
        XCTAssertEqual(filter.apply(to: reviews).map { $0.rating }, [1, 5, 5, 3, 4])
    }

    func testHighestAndLowestRating() {
        var filter = ReviewFilter()
        filter.sort = .highestRating
        XCTAssertEqual(filter.apply(to: reviews).map { $0.rating }, [5, 5, 4, 3, 1])
        filter.sort = .lowestRating
        XCTAssertEqual(filter.apply(to: reviews).map { $0.rating }, [1, 3, 4, 5, 5])
    }

    func testEqualRatingsKeepNewestFirst() {
        var filter = ReviewFilter()
        filter.sort = .highestRating
        let fives = filter.apply(to: reviews).filter { $0.rating == 5 }
        XCTAssertEqual(fives.first?.createdAt, TestCalendar.date(2026, 10, 1))
    }

    func testFilterByRating() {
        var filter = ReviewFilter()
        filter.rating = 5
        XCTAssertEqual(filter.apply(to: reviews).count, 2)
        XCTAssertEqual(filter.activeCount, 1)
    }

    func testOnlyWithCommentIgnoresBlankComments() {
        var filter = ReviewFilter()
        filter.onlyWithComment = true
        XCTAssertEqual(filter.apply(to: reviews).count, 3)
        XCTAssertEqual(ReviewFilter.withComment(in: reviews), 3)
    }

    func testDistributionHasAllFiveStars() {
        let distribution = ReviewFilter.distribution(of: reviews)
        XCTAssertEqual(distribution[5], 2)
        XCTAssertEqual(distribution[4], 1)
        XCTAssertEqual(distribution[3], 1)
        XCTAssertEqual(distribution[2], 0)
        XCTAssertEqual(distribution[1], 1)
    }

    func testResetKeepsSort() {
        var filter = ReviewFilter()
        filter.rating = 4
        filter.onlyWithComment = true
        filter.sort = .lowestRating
        filter.reset()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.sort, .lowestRating)
    }
}
