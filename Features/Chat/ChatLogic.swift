import Foundation

// MARK: - Форматирование времени в переписке
// Свои таблицы месяцев вместо DateFormatter: результат одинаковый на любом устройстве
// и проверяется тестами.
enum ChatTime {

    private static let monthsShort = ["янв", "фев", "мар", "апр", "мая", "июн",
                                      "июл", "авг", "сен", "окт", "ноя", "дек"]
    private static let monthsFull = ["января", "февраля", "марта", "апреля", "мая", "июня",
                                     "июля", "августа", "сентября", "октября", "ноября", "декабря"]

    /// «14:05»
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// «12 окт»
    static func dayMonth(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.day, .month], from: date)
        let month = max(1, min(12, parts.month ?? 1))
        return "\(parts.day ?? 1) \(monthsShort[month - 1])"
    }

    /// «12 октября»
    static func dayMonthFull(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.day, .month], from: date)
        let month = max(1, min(12, parts.month ?? 1))
        return "\(parts.day ?? 1) \(monthsFull[month - 1])"
    }

    private static func isYesterday(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return false }
        return calendar.isDate(date, inSameDayAs: yesterday)
    }

    /// Подпись справа в списке диалогов: сегодня — время, вчера — «вчера», дальше — дата
    static func listStamp(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return clock(date, calendar: calendar) }
        if isYesterday(date, now: now, calendar: calendar) { return "вчера" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return dayMonth(date, calendar: calendar)
        }
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d.%02d.%02d", parts.day ?? 1, parts.month ?? 1, (parts.year ?? 2000) % 100)
    }

    /// Нужен ли заголовок дня перед сообщением: первое в переписке или другой день, чем предыдущее
    static func needsDaySeparator(previous: Date?, current: Date, calendar: Calendar = .current) -> Bool {
        guard let previous else { return true }
        return !calendar.isDate(previous, inSameDayAs: current)
    }

    /// Заголовок дня внутри переписки: «Сегодня», «Вчера», «12 октября»
    static func daySeparator(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Сегодня" }
        if isYesterday(date, now: now, calendar: calendar) { return "Вчера" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return dayMonthFull(date, calendar: calendar)
        }
        return "\(dayMonthFull(date, calendar: calendar)) \(calendar.component(.year, from: date))"
    }
}

// MARK: - Присутствие: в сети / был(а) в сети
// Приложение раз в минуту отмечается в профиле (isOnline + lastSeenAt), а при уходе в фон
// ставит isOnline = false. Если вестей нет дольше двух с половиной минут (приложение
// закрыли принудительно), человек считается не в сети.
struct PresenceInfo: Equatable {
    var isOnline = false
    var lastSeenAt: Date? = nil
    /// Человек разрешил показывать время визита (Приватность). Если нет — только «был(а) недавно».
    var showLastSeen = true

    static let onlineTimeout: TimeInterval = 150

    init(isOnline: Bool = false, lastSeenAt: Date? = nil, showLastSeen: Bool = true) {
        self.isOnline = isOnline
        self.lastSeenAt = lastSeenAt
        self.showLastSeen = showLastSeen
    }

    func isOnlineNow(now: Date = Date()) -> Bool {
        guard isOnline, let seen = lastSeenAt else { return false }
        return now.timeIntervalSince(seen) < PresenceInfo.onlineTimeout
    }

    /// Зелёная точка у аватара. Скрытый статус точку не показывает: иначе его можно было бы вычислить.
    func showsOnlineDot(now: Date = Date()) -> Bool {
        showLastSeen && isOnlineNow(now: now)
    }

    /// Подпись под именем. `nil` — о человеке ничего не известно.
    func statusText(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let seen = lastSeenAt else { return nil }

        if !showLastSeen {
            return PresenceInfo.approximateText(since: seen, now: now)
        }
        if isOnlineNow(now: now) { return "в сети" }

        let seconds = now.timeIntervalSince(seen)
        if seconds < 60 { return "был(а) только что" }
        if seconds < 3600 { return "был(а) \(Int(seconds / 60)) мин назад" }

        let time = ChatTime.clock(seen, calendar: calendar)
        if calendar.isDate(seen, inSameDayAs: now) { return "был(а) сегодня в \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(seen, inSameDayAs: yesterday) {
            return "был(а) вчера в \(time)"
        }
        return "был(а) \(ChatTime.dayMonth(seen, calendar: calendar)) в \(time)"
    }

    /// Приблизительный статус для тех, кто скрыл точное время
    static func approximateText(since seen: Date, now: Date) -> String {
        let days = now.timeIntervalSince(seen) / 86_400
        if days < 3 { return "был(а) недавно" }
        if days < 7 { return "был(а) на этой неделе" }
        if days < 30 { return "был(а) в этом месяце" }
        return "был(а) давно"
    }
}

// MARK: - Предложение другого времени
// Время хранится в заявке строкой «19:00 – 21:00» (так его читает остальной код),
// поэтому здесь считаем в минутах от полуночи и собираем строку в конце.
struct TimeProposal: Equatable {
    var day: Date
    var startMinutes: Int
    var endMinutes: Int

    static let minDuration = 30
    static let maxDuration = 6 * 60

    enum Problem: Equatable {
        case endNotAfterStart, tooShort, tooLong, inPast, unchanged

        var message: String {
            switch self {
            case .endNotAfterStart: return "Конец должен быть позже начала"
            case .tooShort:         return "Встреча короче получаса"
            case .tooLong:          return "Встреча дольше 6 часов"
            case .inPast:           return "Это время уже прошло"
            case .unchanged:        return "Это то же время, что сейчас"
            }
        }
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    var durationMinutes: Int { endMinutes - startMinutes }

    /// «1 ч 30 мин», «2 ч», «45 мин»
    static func durationText(_ minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) мин" }
        if rest == 0 { return "\(hours) ч" }
        return "\(hours) ч \(rest) мин"
    }

    /// «19:00 – 21:00» — в таком виде время хранится в заявке
    var slot: String {
        "\(TimeProposal.clock(startMinutes)) – \(TimeProposal.clock(endMinutes))"
    }

    /// «19 октября, 19:00 – 21:00» — для показа людям
    func summary(calendar: Calendar = .current) -> String {
        "\(ChatTime.dayMonthFull(day, calendar: calendar)), \(slot)"
    }

    /// Первая найденная проблема или `nil`, если время можно предлагать
    func problem(now: Date = Date(),
                 currentDay: Date,
                 currentSlot: String,
                 calendar: Calendar = .current) -> Problem? {
        if endMinutes <= startMinutes { return .endNotAfterStart }
        let duration = endMinutes - startMinutes
        if duration < TimeProposal.minDuration { return .tooShort }
        if duration > TimeProposal.maxDuration { return .tooLong }

        let midnight = calendar.startOfDay(for: day)
        if let start = calendar.date(byAdding: .minute, value: startMinutes, to: midnight), start <= now {
            return .inPast
        }

        if calendar.isDate(day, inSameDayAs: currentDay),
           let current = GameSlot.minutes(from: currentSlot),
           current.start == startMinutes, current.end == endMinutes {
            return .unchanged
        }
        return nil
    }
}

// MARK: - Подтверждение прочтения
enum ReadReceipt {
    /// Моё сообщение прочитано, если партнёр открывал диалог после того, как оно появилось
    static func isRead(sentAt: Date, partnerReadAt: Date?) -> Bool {
        guard let readAt = partnerReadAt else { return false }
        return readAt >= sentAt
    }
}

// MARK: - Ссылка на Apple Карты
// Открывается схемой maps:// — разрешение на геолокацию приложению не нужно.
enum MapsLink {
    /// С координатами — метка в точке; без них — поиск по городу и названию места
    static func url(name: String, city: String, latitude: Double?, longitude: Double?) -> URL? {
        // «&», «=» и подобные внутри названия сломали бы строку запроса
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?/")

        func encode(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        }

        let place = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let town = city.trimmingCharacters(in: .whitespacesAndNewlines)

        if let latitude, let longitude {
            let label = place.isEmpty ? town : place
            var text = "maps://?ll=\(String(format: "%.6f,%.6f", latitude, longitude))"
            if !label.isEmpty { text += "&q=\(encode(label))" }
            return URL(string: text)
        }

        let query = [town, place].filter { !$0.isEmpty }.joined(separator: " ")
        guard !query.isEmpty else { return nil }
        return URL(string: "maps://?q=\(encode(query))")
    }
}
