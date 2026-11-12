import Foundation
@testable import Spinnet

// Общие помощники для тестов

enum TestCalendar {
    /// Григорианский календарь в UTC, неделя с понедельника — результаты не зависят от часового пояса машины
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

/// Матч для тестов. `games` — очки с точки зрения игрока A (автора заявки).
func makeMatch(id: String = UUID().uuidString,
               a: String = "A",
               b: String = "B",
               games: [(Int, Int)],
               format: MatchFormat = .bestOf5,
               status: MatchStatus = .confirmed,
               proposedBy: String? = nil,
               revision: Int = 1,
               playedAt: Date? = nil,
               minutes: Int = 120) -> Match {
    let moment = playedAt ?? TestCalendar.date(2026, 10, 5, 19)
    return Match(
        id: id,
        playerAId: a,
        playerBId: b,
        games: games.map { GameScore(a: $0.0, b: $0.1) },
        format: format,
        status: status,
        proposedBy: proposedBy ?? a,
        revision: revision,
        confirmedBy: status == .confirmed ? b : nil,
        playedAt: moment,
        slotMinutes: minutes,
        city: "Томск",
        createdAt: moment,
        updatedAt: moment,
        previousGames: nil,
        previousProposedBy: nil
    )
}
