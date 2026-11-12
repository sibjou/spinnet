import Foundation

// MARK: - Фильтры и сортировка историй в профиле
// Чистая логика без SwiftUI: что показать из списка игр, матчей и отзывов.
// Экран только рисует кнопки и отдаёт сюда выбранные значения — всё проверяется тестами.

// MARK: Когда показывать панель фильтров
// Для трёх игр панель только мешает; когда записей набралось, без неё уже трудно

enum FilterThreshold {
    static let games = 4
    static let matches = 5
    static let reviews = 3
}

// MARK: Месяц

struct YearMonth: Hashable, Comparable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.year = parts.year ?? 0
        self.month = parts.month ?? 1
    }

    nonisolated static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        lhs.year != rhs.year ? lhs.year < rhs.year : lhs.month < rhs.month
    }

    /// Первое число месяца — из него экран делает подпись «Октябрь 2026»
    func firstDay(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }
}

// MARK: Период

enum HistoryPeriod: Hashable {
    case allTime
    case last7Days
    case last30Days
    case last90Days
    case thisYear
    case month(YearMonth)

    /// Быстрые варианты; конкретные месяцы экран добавляет сам — только те, где что-то было
    static let quick: [HistoryPeriod] = [.allTime, .last7Days, .last30Days, .last90Days, .thisYear]

    var isAllTime: Bool { self == .allTime }

    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .allTime:
            return true
        case .last7Days:
            return date >= startOfLast(days: 7, now: now, calendar: calendar)
        case .last30Days:
            return date >= startOfLast(days: 30, now: now, calendar: calendar)
        case .last90Days:
            return date >= startOfLast(days: 90, now: now, calendar: calendar)
        case .thisYear:
            return calendar.component(.year, from: date) == calendar.component(.year, from: now)
        case .month(let target):
            return YearMonth(date, calendar: calendar) == target
        }
    }

    /// Начало периода «последние N дней»: сегодняшний день считается за один из N
    private func startOfLast(days: Int, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
    }
}

/// Месяц, в котором есть записи, и сколько их
struct MonthBucket: Equatable {
    let month: YearMonth
    let count: Int
}

enum HistoryBuckets {

    /// Месяцы, в которых что-то было: новые сверху
    static func months(of dates: [Date], calendar: Calendar = .current) -> [MonthBucket] {
        var counts: [YearMonth: Int] = [:]
        for date in dates { counts[YearMonth(date, calendar: calendar), default: 0] += 1 }
        return counts
            .map { MonthBucket(month: $0.key, count: $0.value) }
            .sorted { $0.month > $1.month }
    }

    /// Группы подряд идущих записей одного месяца (для заголовков «Октябрь 2026»)
    static func groupedByMonth<T>(_ items: [T], date: (T) -> Date,
                                  calendar: Calendar = .current) -> [MonthGroup<T>] {
        var result: [MonthGroup<T>] = []
        for item in items {
            let month = YearMonth(date(item), calendar: calendar)
            if let last = result.last, last.month == month {
                result[result.count - 1].items.append(item)
            } else {
                result.append(MonthGroup(month: month, items: [item]))
            }
        }
        return result
    }
}

/// Записи одного месяца подряд
struct MonthGroup<T>: Identifiable {
    let month: YearMonth
    var items: [T]

    var id: YearMonth { month }
}

// MARK: Сортировка

enum HistorySort: CaseIterable, Hashable {
    case newestFirst
    case oldestFirst
    case byOpponent

    /// По дате — можно делить на месяцы; по имени — нет
    var isByDate: Bool { self != .byOpponent }
}

// MARK: - Игры

struct HistoryGame: Identifiable, Equatable {
    enum Role { case author, partner }

    let id: String
    let date: Date
    let role: Role
    let partnerId: String
    let partnerName: String
    /// Город так, как записан в заявке
    let city: String
    /// Город для показа: «Мурманск », «мурманск» и «Мурманска» — один «Мурманск» (см. `CityName`)
    let cityName: String
    /// По нему игры группируются и фильтруются; считается один раз, а не на каждое нажатие в поиске
    let cityKey: String
    let place: String
    /// false — встреча не состоялась (заявка истекла)
    let wasHeld: Bool
    /// Подтверждённые матчи этой встречи с моей стороны
    let matchesWon: Int
    let matchesLost: Int

    var hasScore: Bool { matchesWon + matchesLost > 0 }

    init(id: String, date: Date, role: Role, partnerId: String, partnerName: String,
         city: String, place: String, wasHeld: Bool, matchesWon: Int, matchesLost: Int) {
        self.id = id
        self.date = date
        self.role = role
        self.partnerId = partnerId
        self.partnerName = partnerName
        self.city = city
        self.cityName = CityName.canonical(city)
        self.cityKey = CityName.key(self.cityName)
        self.place = place
        self.wasHeld = wasHeld
        self.matchesWon = matchesWon
        self.matchesLost = matchesLost
    }
}

enum GameRoleFilter: CaseIterable, Hashable {
    case any
    case created     // заявку создал я
    case joined      // я откликнулся на чужую

    func allows(_ game: HistoryGame) -> Bool {
        switch self {
        case .any:    return true
        case .created: return game.role == .author
        case .joined:  return game.role == .partner
        }
    }
}

enum GameOutcomeFilter: CaseIterable, Hashable {
    case any
    case won         // больше выигранных матчей, чем проигранных
    case lost
    case noScore     // сыграли, но счёт не внесён или не подтверждён
    case notHeld     // не состоялась

    func allows(_ game: HistoryGame) -> Bool {
        switch self {
        case .any:      return true
        case .won:      return game.wasHeld && game.matchesWon > game.matchesLost
        case .lost:     return game.wasHeld && game.matchesLost > game.matchesWon
        case .noScore:  return game.wasHeld && !game.hasScore
        case .notHeld:  return !game.wasHeld
        }
    }
}

struct GameHistoryFilter: Equatable {
    var period: HistoryPeriod = .allTime
    var role: GameRoleFilter = .any
    var outcome: GameOutcomeFilter = .any
    var city: String? = nil
    var query: String = ""
    var sort: HistorySort = .newestFirst

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Сколько условий включено (сортировка — не условие)
    var activeCount: Int {
        var count = 0
        if !period.isAllTime { count += 1 }
        if role != .any { count += 1 }
        if outcome != .any { count += 1 }
        if city != nil { count += 1 }
        if !trimmedQuery.isEmpty { count += 1 }
        return count
    }

    var isActive: Bool { activeCount > 0 }

    /// Сбрасывает условия, порядок сортировки остаётся
    mutating func reset() {
        period = .allTime
        role = .any
        outcome = .any
        city = nil
        query = ""
    }

    func apply(to games: [HistoryGame], now: Date = Date(), calendar: Calendar = .current) -> [HistoryGame] {
        let text = trimmedQuery
        let cityKey = city.map { CityName.groupKey($0) }
        let filtered = games.filter { game in
            guard period.contains(game.date, now: now, calendar: calendar),
                  role.allows(game),
                  outcome.allows(game) else { return false }
            if let cityKey, game.cityKey != cityKey { return false }
            if !text.isEmpty {
                let haystack = [game.partnerName, game.cityName, game.place]
                if !haystack.contains(where: { $0.localizedCaseInsensitiveContains(text) }) { return false }
            }
            return true
        }
        return Self.sorted(filtered, by: sort)
    }

    static func sorted(_ games: [HistoryGame], by sort: HistorySort) -> [HistoryGame] {
        switch sort {
        case .newestFirst:
            return games.sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
        case .oldestFirst:
            return games.sorted { $0.date != $1.date ? $0.date < $1.date : $0.id < $1.id }
        case .byOpponent:
            return games.sorted { first, second in
                let order = first.partnerName.localizedCaseInsensitiveCompare(second.partnerName)
                if order != .orderedSame { return order == .orderedAscending }
                return first.date != second.date ? first.date > second.date : first.id < second.id
            }
        }
    }

    /// Города, где есть игры: самые частые первыми. Один город — один пункт, как бы он ни был написан в заявках
    static func cities(in games: [HistoryGame]) -> [String] {
        var counts: [String: Int] = [:]                // ключ города → сколько игр
        var spellings: [String: [String: Int]] = [:]   // ключ → как называли → сколько раз
        for game in games where !game.cityKey.isEmpty {
            counts[game.cityKey, default: 0] += 1
            spellings[game.cityKey, default: [:]][game.cityName, default: 0] += 1
        }
        let order = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        return order.compactMap { entry in
            // Название — самое частое написание (при равенстве — по алфавиту)
            spellings[entry.key]?
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .first?.key
        }
    }

    /// Сколько игр подходит под вариант результата (для подписей в меню)
    static func count(of outcome: GameOutcomeFilter, in games: [HistoryGame]) -> Int {
        games.filter { outcome.allows($0) }.count
    }
}

// MARK: - Матчи

struct HistoryMatch: Identifiable, Equatable {
    let id: String
    let date: Date
    let opponentId: String
    let opponentName: String
    let won: Bool
    let gamesWon: Int
    let gamesLost: Int
    let ordinal: Int
}

enum MatchResultFilter: CaseIterable, Hashable {
    case any, won, lost

    func allows(_ match: HistoryMatch) -> Bool {
        switch self {
        case .any:  return true
        case .won:  return match.won
        case .lost: return !match.won
        }
    }
}

struct MatchHistoryFilter: Equatable {
    var period: HistoryPeriod = .allTime
    var result: MatchResultFilter = .any
    var query: String = ""
    var sort: HistorySort = .newestFirst

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var activeCount: Int {
        var count = 0
        if !period.isAllTime { count += 1 }
        if result != .any { count += 1 }
        if !trimmedQuery.isEmpty { count += 1 }
        return count
    }

    var isActive: Bool { activeCount > 0 }

    mutating func reset() {
        period = .allTime
        result = .any
        query = ""
    }

    func apply(to matches: [HistoryMatch], now: Date = Date(), calendar: Calendar = .current) -> [HistoryMatch] {
        let text = trimmedQuery
        let filtered = matches.filter { match in
            guard period.contains(match.date, now: now, calendar: calendar),
                  result.allows(match) else { return false }
            if !text.isEmpty, !match.opponentName.localizedCaseInsensitiveContains(text) { return false }
            return true
        }
        switch sort {
        case .newestFirst:
            return filtered.sorted { $0.date != $1.date ? $0.date > $1.date : $0.ordinal > $1.ordinal }
        case .oldestFirst:
            return filtered.sorted { $0.date != $1.date ? $0.date < $1.date : $0.ordinal < $1.ordinal }
        case .byOpponent:
            return filtered.sorted { first, second in
                let order = first.opponentName.localizedCaseInsensitiveCompare(second.opponentName)
                if order != .orderedSame { return order == .orderedAscending }
                return first.date != second.date ? first.date > second.date : first.ordinal > second.ordinal
            }
        }
    }

    static func count(of result: MatchResultFilter, in matches: [HistoryMatch]) -> Int {
        matches.filter { result.allows($0) }.count
    }
}

// MARK: - Отзывы

protocol RatedReview {
    var rating: Int { get }
    var comment: String { get }
    var createdAt: Date { get }
}

enum ReviewSort: CaseIterable, Hashable {
    case newest
    case oldest
    case highestRating
    case lowestRating
}

struct ReviewFilter: Equatable {
    /// nil — все оценки
    var rating: Int? = nil
    var onlyWithComment = false
    var sort: ReviewSort = .newest

    var activeCount: Int { (rating != nil ? 1 : 0) + (onlyWithComment ? 1 : 0) }
    var isActive: Bool { activeCount > 0 }

    mutating func reset() {
        rating = nil
        onlyWithComment = false
    }

    func apply<R: RatedReview>(to reviews: [R]) -> [R] {
        let filtered = reviews.filter { review in
            if let rating, review.rating != rating { return false }
            if onlyWithComment, review.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            return true
        }
        switch sort {
        case .newest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .highestRating:
            return filtered.sorted { $0.rating != $1.rating ? $0.rating > $1.rating : $0.createdAt > $1.createdAt }
        case .lowestRating:
            return filtered.sorted { $0.rating != $1.rating ? $0.rating < $1.rating : $0.createdAt > $1.createdAt }
        }
    }

    /// Сколько отзывов с каждой оценкой от 1 до 5 (нулевые тоже есть в словаре)
    static func distribution<R: RatedReview>(of reviews: [R]) -> [Int: Int] {
        var counts = Dictionary(uniqueKeysWithValues: (1...5).map { ($0, 0) })
        for review in reviews where (1...5).contains(review.rating) { counts[review.rating, default: 0] += 1 }
        return counts
    }

    static func withComment<R: RatedReview>(in reviews: [R]) -> Int {
        reviews.filter { !$0.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
}
