import Foundation

// MARK: - Части дня (для тепловой карты)
enum DayPart: Int, CaseIterable, Identifiable {
    case morning = 0     // 6–12
    case afternoon       // 12–17
    case evening         // 17–22
    case night           // 22–6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .morning:   return "Утро"
        case .afternoon: return "День"
        case .evening:   return "Вечер"
        case .night:     return "Ночь"
        }
    }

    static func part(forHour hour: Int) -> DayPart {
        switch hour {
        case 6..<12:  return .morning
        case 12..<17: return .afternoon
        case 17..<22: return .evening
        default:      return .night
        }
    }
}

// MARK: - Результат расчёта

struct WeekBucket: Equatable, Identifiable {
    let weekStart: Date
    let matches: Int
    let wins: Int
    let minutes: Int
    var id: Date { weekStart }
}

struct HeatCell: Equatable, Identifiable {
    let weekday: Int          // 1 = понедельник … 7 = воскресенье
    let dayPart: DayPart
    let count: Int
    var id: Int { weekday * 10 + dayPart.rawValue }
}

struct TrendPoint: Equatable, Identifiable {
    let index: Int            // порядковый номер матча, с 1
    let date: Date
    let winRate: Double       // 0…1 за последние матчи окна
    var id: Int { index }
}

struct HeadToHead: Equatable, Identifiable {
    let opponentId: String
    let matches: Int
    let wins: Int
    let pointsWon: Int
    let pointsLost: Int
    let lastPlayed: Date
    var losses: Int { matches - wins }
    var id: String { opponentId }
}

struct PlayerStats: Equatable {
    var matches = 0
    var wins = 0
    var losses: Int { matches - wins }
    var winRate: Double { matches == 0 ? 0 : Double(wins) / Double(matches) }

    var gamesWon = 0
    var gamesLost = 0
    var pointsWon = 0
    var pointsLost = 0

    /// > 0 — серия побед, < 0 — серия поражений
    var currentStreak = 0
    var bestWinStreak = 0

    var totalMinutes = 0
    var totalHours: Double { Double(totalMinutes) / 60 }

    var uniqueOpponents = 0

    /// Матчи, дошедшие до решающей партии, и сколько из них выиграно
    var deciderMatches = 0
    var deciderWins = 0

    /// Последние матчи, от старых к новым: true — победа
    var form: [Bool] = []

    var weekly: [WeekBucket] = []
    var heatmap: [HeatCell] = []
    var trend: [TrendPoint] = []
    var headToHead: [HeadToHead] = []

    /// Средняя разница очков за матч
    var averagePointDifference: Double {
        matches == 0 ? 0 : Double(pointsWon - pointsLost) / Double(matches)
    }

    static let empty = PlayerStats()
}

// MARK: - Расчёт статистики
// Чистая функция от списка матчей. В расчёт идут только подтверждённые матчи
// с корректным счётом, в которых участвует игрок.
enum StatsCalculator {

    static let weeksShown = 12
    static let formLength = 10
    static let trendWindow = 10

    static func compute(matches allMatches: [Match],
                        userId: String,
                        now: Date = Date(),
                        calendar baseCalendar: Calendar = .current) -> PlayerStats {

        var calendar = baseCalendar
        calendar.firstWeekday = 2             // неделя с понедельника
        calendar.minimumDaysInFirstWeek = 4

        let counted = allMatches
            .filter { $0.involves(userId) && $0.isCounted }
            .sorted { first, second in
                // Матчи одной встречи идут в порядке их внесения
                first.playedAt != second.playedAt ? first.playedAt < second.playedAt : first.ordinal < second.ordinal
            }

        var stats = PlayerStats()
        var results: [(match: Match, perspective: Match.Perspective)] = []
        for match in counted {
            if let perspective = match.perspective(of: userId) {
                results.append((match, perspective))
            }
        }

        guard !results.isEmpty else {
            stats.weekly = weeklyBuckets(results: [], now: now, calendar: calendar)
            stats.heatmap = heatmap(results: [], calendar: calendar)
            return stats
        }

        // Итоги
        var opponents = Set<String>()
        for (match, p) in results {
            stats.matches += 1
            if p.won { stats.wins += 1 }
            stats.gamesWon   += p.gamesWon
            stats.gamesLost  += p.gamesLost
            stats.pointsWon  += p.pointsWon
            stats.pointsLost += p.pointsLost
            stats.totalMinutes += match.slotMinutes
            if let opponent = match.opponentId(of: userId) { opponents.insert(opponent) }
            if match.wentToDecider {
                stats.deciderMatches += 1
                if p.won { stats.deciderWins += 1 }
            }
        }
        stats.uniqueOpponents = opponents.count

        // Серии
        let outcomes = results.map { $0.perspective.won }
        stats.currentStreak = currentStreak(outcomes)
        stats.bestWinStreak = bestWinStreak(outcomes)
        stats.form = Array(outcomes.suffix(formLength))

        // Графики
        stats.weekly = weeklyBuckets(results: results, now: now, calendar: calendar)
        stats.heatmap = heatmap(results: results, calendar: calendar)
        stats.trend = trendPoints(results: results)
        stats.headToHead = headToHead(results: results, userId: userId)

        return stats
    }

    // MARK: - Серии

    static func currentStreak(_ outcomes: [Bool]) -> Int {
        guard let last = outcomes.last else { return 0 }
        var length = 0
        for outcome in outcomes.reversed() {
            if outcome == last { length += 1 } else { break }
        }
        return last ? length : -length
    }

    static func bestWinStreak(_ outcomes: [Bool]) -> Int {
        var best = 0, current = 0
        for outcome in outcomes {
            current = outcome ? current + 1 : 0
            best = max(best, current)
        }
        return best
    }

    // MARK: - Активность по неделям

    private static func weeklyBuckets(results: [(match: Match, perspective: Match.Perspective)],
                                      now: Date,
                                      calendar: Calendar) -> [WeekBucket] {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }

        var buckets: [WeekBucket] = []
        for offset in stride(from: weeksShown - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { continue }

            let inWeek = results.filter { $0.match.playedAt >= start && $0.match.playedAt < end }
            buckets.append(WeekBucket(
                weekStart: start,
                matches: inWeek.count,
                wins: inWeek.filter { $0.perspective.won }.count,
                minutes: inWeek.reduce(0) { $0 + $1.match.slotMinutes }
            ))
        }
        return buckets
    }

    // MARK: - Тепловая карта «день недели × время суток»

    private static func heatmap(results: [(match: Match, perspective: Match.Perspective)],
                                calendar: Calendar) -> [HeatCell] {
        var counts: [Int: Int] = [:]
        for (match, _) in results {
            let weekday = mondayFirstWeekday(match.playedAt, calendar: calendar)
            let part = DayPart.part(forHour: calendar.component(.hour, from: match.playedAt))
            counts[weekday * 10 + part.rawValue, default: 0] += 1
        }

        var cells: [HeatCell] = []
        for weekday in 1...7 {
            for part in DayPart.allCases {
                cells.append(HeatCell(
                    weekday: weekday,
                    dayPart: part,
                    count: counts[weekday * 10 + part.rawValue] ?? 0
                ))
            }
        }
        return cells
    }

    /// 1 = понедельник … 7 = воскресенье
    static func mondayFirstWeekday(_ date: Date, calendar: Calendar) -> Int {
        let sundayFirst = calendar.component(.weekday, from: date)   // 1 = воскресенье
        return (sundayFirst + 5) % 7 + 1
    }

    // MARK: - Динамика процента побед (скользящее окно)

    private static func trendPoints(results: [(match: Match, perspective: Match.Perspective)]) -> [TrendPoint] {
        var points: [TrendPoint] = []
        let outcomes = results.map { $0.perspective.won }

        for index in outcomes.indices where index >= 2 {      // от третьего матча
            let lowerBound = max(0, index + 1 - trendWindow)
            let window = outcomes[lowerBound...index]
            let wins = window.filter { $0 }.count
            points.append(TrendPoint(
                index: index + 1,
                date: results[index].match.playedAt,
                winRate: Double(wins) / Double(window.count)
            ))
        }
        return points
    }

    // MARK: - Личные встречи с соперниками

    private static func headToHead(results: [(match: Match, perspective: Match.Perspective)],
                                   userId: String) -> [HeadToHead] {
        var grouped: [String: [(match: Match, perspective: Match.Perspective)]] = [:]
        for item in results {
            guard let opponent = item.match.opponentId(of: userId) else { continue }
            grouped[opponent, default: []].append(item)
        }

        return grouped.map { opponent, items in
            HeadToHead(
                opponentId: opponent,
                matches: items.count,
                wins: items.filter { $0.perspective.won }.count,
                pointsWon: items.reduce(0) { $0 + $1.perspective.pointsWon },
                pointsLost: items.reduce(0) { $0 + $1.perspective.pointsLost },
                lastPlayed: items.map { $0.match.playedAt }.max() ?? Date.distantPast
            )
        }
        .sorted {
            if $0.matches != $1.matches { return $0.matches > $1.matches }
            if $0.lastPlayed != $1.lastPlayed { return $0.lastPlayed > $1.lastPlayed }
            return $0.opponentId < $1.opponentId
        }
    }

    /// Личные встречи двух игроков (для блока «Ваши встречи» в чужом профиле)
    static func headToHead(matches: [Match], userId: String, opponentId: String) -> HeadToHead? {
        let stats = compute(matches: matches.filter { $0.involves(opponentId) }, userId: userId)
        return stats.headToHead.first { $0.opponentId == opponentId }
    }
}
