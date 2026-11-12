import XCTest
@testable import Spinnet

final class StatsCalculatorTests: XCTestCase {

    private let now = TestCalendar.date(2026, 10, 14, 12)          // среда
    private let calendar = TestCalendar.utc

    private func stats(_ matches: [Match], user: String = "A") -> PlayerStats {
        StatsCalculator.compute(matches: matches, userId: user, now: now, calendar: calendar)
    }

    // Набор из четырёх матчей игрока A (посчитан вручную)
    //  1. пн 5 окт 19:00  с B: 3:0 победа       (A — игрок A)
    //  2. ср 7 окт 10:00  с B: 1:3 поражение    (A — игрок B, очки записаны со стороны B)
    //  3. пн 12 окт 19:00 с C: 3:2 победа, решающая партия
    //  4. вт 13 окт 23:00 с C: 2:0 победа, bo3
    private var sample: [Match] {
        [
            makeMatch(a: "A", b: "B",
                      games: [(11, 5), (11, 7), (11, 9)],
                      playedAt: TestCalendar.date(2026, 10, 5, 19)),
            makeMatch(a: "B", b: "A",
                      games: [(11, 8), (9, 11), (11, 5), (11, 7)],
                      playedAt: TestCalendar.date(2026, 10, 7, 10)),
            makeMatch(a: "A", b: "C",
                      games: [(11, 9), (9, 11), (11, 8), (8, 11), (12, 10)],
                      playedAt: TestCalendar.date(2026, 10, 12, 19)),
            makeMatch(a: "A", b: "C",
                      games: [(11, 3), (11, 4)],
                      format: .bestOf3,
                      playedAt: TestCalendar.date(2026, 10, 13, 23))
        ]
    }

    func testTotals() {
        let s = stats(sample)
        XCTAssertEqual(s.matches, 4)
        XCTAssertEqual(s.wins, 3)
        XCTAssertEqual(s.losses, 1)
        XCTAssertEqual(s.winRate, 0.75, accuracy: 0.0001)
        XCTAssertEqual(s.gamesWon, 9)
        XCTAssertEqual(s.gamesLost, 5)
        XCTAssertEqual(s.pointsWon, 137)
        XCTAssertEqual(s.pointsLost, 119)
        XCTAssertEqual(s.averagePointDifference, 4.5, accuracy: 0.0001)
        XCTAssertEqual(s.totalMinutes, 480)
        XCTAssertEqual(s.totalHours, 8, accuracy: 0.0001)
        XCTAssertEqual(s.uniqueOpponents, 2)
        XCTAssertEqual(s.deciderMatches, 1)
        XCTAssertEqual(s.deciderWins, 1)
    }

    func testSamePerspectiveForTheOtherPlayer() {
        let s = stats(sample, user: "C")
        XCTAssertEqual(s.matches, 2)
        XCTAssertEqual(s.wins, 0)
        XCTAssertEqual(s.currentStreak, -2)
        XCTAssertEqual(s.deciderMatches, 1)
        XCTAssertEqual(s.deciderWins, 0)
    }

    func testStreaksAndForm() {
        let s = stats(sample)
        XCTAssertEqual(s.currentStreak, 2)
        XCTAssertEqual(s.bestWinStreak, 2)
        XCTAssertEqual(s.form, [true, false, true, true])

        XCTAssertEqual(StatsCalculator.currentStreak([true, false, false]), -2)
        XCTAssertEqual(StatsCalculator.currentStreak([]), 0)
        XCTAssertEqual(StatsCalculator.bestWinStreak([true, true, false, true, true, true, false]), 3)
    }

    func testFormKeepsLastTen() {
        let many = (0..<14).map { index in
            makeMatch(games: [(11, 5), (11, 5), (11, 5)],
                      playedAt: TestCalendar.date(2026, 9, 1 + index, 18))
        }
        XCTAssertEqual(stats(many).form.count, 10)
    }

    func testWeeklyActivity() {
        let weekly = stats(sample).weekly
        XCTAssertEqual(weekly.count, 12)
        XCTAssertEqual(weekly.first?.weekStart, TestCalendar.date(2026, 7, 27, 0))
        XCTAssertEqual(weekly.last?.weekStart, TestCalendar.date(2026, 10, 12, 0))

        XCTAssertEqual(weekly.last?.matches, 2)
        XCTAssertEqual(weekly.last?.wins, 2)
        XCTAssertEqual(weekly.last?.minutes, 240)
        XCTAssertEqual(weekly[10].matches, 2)
        XCTAssertEqual(weekly[10].wins, 1)
        XCTAssertEqual(weekly.dropLast(2).reduce(0) { $0 + $1.matches }, 0)
    }

    func testHeatmap() {
        let cells = stats(sample).heatmap
        XCTAssertEqual(cells.count, 28)
        func count(_ weekday: Int, _ part: DayPart) -> Int {
            cells.first { $0.weekday == weekday && $0.dayPart == part }?.count ?? -1
        }
        XCTAssertEqual(count(1, .evening), 2)     // два понедельничных вечера
        XCTAssertEqual(count(3, .morning), 1)     // среда утром
        XCTAssertEqual(count(2, .night), 1)       // вторник 23:00
        XCTAssertEqual(cells.reduce(0) { $0 + $1.count }, 4)
    }

    func testWeekdayMapping() {
        // 12 октября 2026 — понедельник, 18-е — воскресенье
        XCTAssertEqual(StatsCalculator.mondayFirstWeekday(TestCalendar.date(2026, 10, 12), calendar: calendar), 1)
        XCTAssertEqual(StatsCalculator.mondayFirstWeekday(TestCalendar.date(2026, 10, 17), calendar: calendar), 6)
        XCTAssertEqual(StatsCalculator.mondayFirstWeekday(TestCalendar.date(2026, 10, 18), calendar: calendar), 7)
    }

    func testDayParts() {
        XCTAssertEqual(DayPart.part(forHour: 6), .morning)
        XCTAssertEqual(DayPart.part(forHour: 11), .morning)
        XCTAssertEqual(DayPart.part(forHour: 12), .afternoon)
        XCTAssertEqual(DayPart.part(forHour: 17), .evening)
        XCTAssertEqual(DayPart.part(forHour: 21), .evening)
        XCTAssertEqual(DayPart.part(forHour: 22), .night)
        XCTAssertEqual(DayPart.part(forHour: 3), .night)
    }

    func testTrend() {
        let trend = stats(sample).trend
        XCTAssertEqual(trend.count, 2)                  // с третьего матча
        XCTAssertEqual(trend[0].index, 3)
        XCTAssertEqual(trend[0].winRate, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(trend[1].index, 4)
        XCTAssertEqual(trend[1].winRate, 0.75, accuracy: 0.0001)
    }

    func testHeadToHead() {
        let h2h = stats(sample).headToHead
        XCTAssertEqual(h2h.map { $0.opponentId }, ["C", "B"])      // при равенстве — свежее выше
        XCTAssertEqual(h2h[0].matches, 2)
        XCTAssertEqual(h2h[0].wins, 2)
        XCTAssertEqual(h2h[1].matches, 2)
        XCTAssertEqual(h2h[1].wins, 1)
        XCTAssertEqual(h2h[1].losses, 1)
        XCTAssertEqual(h2h[1].pointsWon, 33 + 31)
        XCTAssertEqual(h2h[1].pointsLost, 21 + 42)

        let direct = StatsCalculator.headToHead(matches: sample, userId: "A", opponentId: "B")
        XCTAssertEqual(direct?.matches, 2)
        XCTAssertNil(StatsCalculator.headToHead(matches: sample, userId: "A", opponentId: "Z"))
    }

    func testOnlyConfirmedValidMatchesAreCounted() {
        let ignored = [
            makeMatch(games: [(11, 5), (11, 5), (11, 5)], status: .proposed),
            makeMatch(games: [(11, 5), (11, 5), (11, 5)], status: .disputed),
            makeMatch(games: [(11, 10), (11, 5), (11, 5)], status: .confirmed),      // невозможный счёт
            makeMatch(a: "X", b: "Y", games: [(11, 5), (11, 5), (11, 5)])             // чужой матч
        ]
        let s = stats(ignored + [makeMatch(games: [(11, 5), (11, 5), (11, 5)])])
        XCTAssertEqual(s.matches, 1)
        XCTAssertEqual(s.wins, 1)
    }

    func testEmptyStats() {
        let s = stats([])
        XCTAssertEqual(s.matches, 0)
        XCTAssertEqual(s.winRate, 0)
        XCTAssertEqual(s.averagePointDifference, 0)
        XCTAssertEqual(s.weekly.count, 12)
        XCTAssertEqual(s.heatmap.count, 28)
        XCTAssertTrue(s.trend.isEmpty)
        XCTAssertTrue(s.headToHead.isEmpty)
        XCTAssertEqual(s.currentStreak, 0)
    }
}
