import Foundation

// MARK: - Правила ленты
// Чистая логика без SwiftUI и Firebase: проверяется тестами.
// Лента показывает то, что можно сыграть: в моём городе, в ближайшее время, по моему уровню.

// MARK: Город
// Два города у человека: домашний (из профиля) и «где ищу» (если уехал или хочет посмотреть другой).
// Выбирать город каждый раз не нужно: по умолчанию лента следует за профилем. Выбор в ленте запоминается,
// а если выбран домашний город, запоминать нечего — лента снова следует за профилем.

enum FeedCity {

    /// Пункт «без фильтра по городу»
    static let all = "Все города"

    /// Какой город показывать.
    /// - `home`: город из профиля (может быть пустым)
    /// - `saved`: что человек выбрал в ленте раньше; `nil` — не выбирал
    static func effective(home: String, saved: String?) -> String {
        if let saved, !saved.isEmpty { return saved }
        let city = CityName.canonical(home)
        return city.isEmpty ? all : city
    }

    /// Что запомнить после выбора города в ленте. `nil` — ничего: лента следует за профилем.
    static func savedValue(chosen: String, home: String) -> String? {
        let picked = CityName.canonical(chosen)
        if chosen == all || picked.isEmpty { return all }
        if !home.isEmpty, CityName.same(picked, home) { return nil }
        return picked
    }

    /// Ключ в UserDefaults: у каждого аккаунта на телефоне свой выбор
    static func storageKey(userId: String) -> String { "feed.city.\(userId)" }
}

// MARK: День

enum FeedDay: String, CaseIterable, Equatable {
    case any, today, tomorrow, weekend

    var title: String {
        switch self {
        case .any:      return "Любой день"
        case .today:    return "Сегодня"
        case .tomorrow: return "Завтра"
        case .weekend:  return "Выходные"
        }
    }

    /// Подходит ли день заявки под выбор
    func matches(_ day: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .any:
            return true
        case .today:
            return calendar.isDate(day, inSameDayAs: now)
        case .tomorrow:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return false }
            return calendar.isDate(day, inSameDayAs: tomorrow)
        case .weekend:
            // 1 — воскресенье, 7 — суббота, в любом календаре и языке
            let weekday = calendar.component(.weekday, from: day)
            return weekday == 1 || weekday == 7
        }
    }
}

// MARK: Время заявки

enum RequestTiming {

    /// Игра ещё не закончилась. Если время не разобралось, заявка живёт до конца дня.
    static func isUpcoming(day: Date, slot: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let midnight = calendar.startOfDay(for: day)
        if let range = GameSlot.minutes(from: slot),
           let end = calendar.date(byAdding: .minute, value: range.end, to: midnight) {
            return end > now
        }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: midnight) else { return true }
        return nextDay > now
    }

    /// Момент начала игры: по нему лента сортируется от ближайшей к дальней
    static func sortKey(day: Date, slot: String, calendar: Calendar = .current) -> Date {
        GameSlot.startDate(day: day, slot: slot, calendar: calendar) ?? calendar.startOfDay(for: day)
    }

    /// Игра идёт прямо сейчас: началась и ещё не закончилась
    static func isInProgress(day: Date, slot: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let range = GameSlot.minutes(from: slot) else { return false }
        let midnight = calendar.startOfDay(for: day)
        guard let start = calendar.date(byAdding: .minute, value: range.start, to: midnight),
              let end = calendar.date(byAdding: .minute, value: range.end, to: midnight) else { return false }
        return start <= now && now < end
    }

    /// «Сегодня» или «Завтра»; для остальных дней — nil, и на экране показывается дата
    static func dayWord(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> String? {
        if FeedDay.today.matches(day, now: now, calendar: calendar) { return "Сегодня" }
        if FeedDay.tomorrow.matches(day, now: now, calendar: calendar) { return "Завтра" }
        return nil
    }
}

// MARK: - Порядок

enum FeedOrder {

    /// От ближайшей игры к дальней. Если время совпало, выше та заявка, которую создали позже.
    static func sorted<T>(_ items: [T],
                          day: (T) -> Date,
                          slot: (T) -> String,
                          createdAt: (T) -> Date,
                          calendar: Calendar = .current) -> [T] {
        let keyed = items.map { item in
            (item: item,
             start: RequestTiming.sortKey(day: day(item), slot: slot(item), calendar: calendar),
             created: createdAt(item))
        }
        return keyed.sorted { first, second in
            first.start != second.start ? first.start < second.start : first.created > second.created
        }.map { $0.item }
    }
}

// MARK: Уровень

enum LevelMatch {

    /// От слабого к сильному
    static let order = ["Начинающий", "Любитель", "Продвинутый", "Профессионал"]

    static func index(_ level: String) -> Int? {
        order.firstIndex(of: level)
    }

    /// Заявка подходит по уровню: автор не дальше одной ступени от меня,
    /// а если он ищет конкретный уровень — это мой уровень.
    /// Если свой уровень неизвестен, ничего не отсеиваем.
    static func fits(myLevel: String, authorLevel: String, desiredLevel: String) -> Bool {
        guard let mine = index(myLevel) else { return true }
        if let author = index(authorLevel), abs(author - mine) > 1 { return false }
        if let wanted = index(desiredLevel), wanted != mine { return false }
        return true
    }

    /// Сколько делений из четырёх закрашивать в индикаторе уровня (0 — уровень неизвестен)
    static func bars(_ level: String) -> Int {
        (index(level) ?? -1) + 1
    }
}

// MARK: - Группы по дням
// Лента идёт от ближайшей игры к дальней, а заголовки «Сегодня», «Завтра», «Суббота, 17 октября» делят её на дни:
// дата не повторяется в каждой карточке, и сразу видно, что список упорядочен по времени.

struct FeedDaySection<Item>: Identifiable {
    /// Начало дня
    let day: Date
    let items: [Item]
    var id: TimeInterval { day.timeIntervalSince1970 }
}

enum FeedGrouping {

    /// Подряд идущие элементы одного дня собираются в раздел. Порядок элементов не меняется.
    static func sections<Item>(_ items: [Item],
                               day: (Item) -> Date,
                               calendar: Calendar = .current) -> [FeedDaySection<Item>] {
        var result: [FeedDaySection<Item>] = []
        var currentDay: Date?
        var bucket: [Item] = []

        for item in items {
            let start = calendar.startOfDay(for: day(item))
            if let currentDay, currentDay == start {
                bucket.append(item)
            } else {
                if let currentDay { result.append(FeedDaySection(day: currentDay, items: bucket)) }
                currentDay = start
                bucket = [item]
            }
        }
        if let currentDay { result.append(FeedDaySection(day: currentDay, items: bucket)) }
        return result
    }

    /// Заголовок раздела: «Сегодня, 15 октября», «Завтра, 16 октября», «Суббота, 17 октября»
    static func title(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if let word = RequestTiming.dayWord(for: day, now: now, calendar: calendar) {
            return "\(word), \(AppDate.dayLong(day))"
        }
        let text = AppDate.weekdayDayLong(day)
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
