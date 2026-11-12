import Foundation

// MARK: - Уведомления по дням
// Лента уведомлений делится на «Сегодня», «Вчера» и даты: так видно, что новое, а что давно.

enum NotificationGrouping {

    /// Только то, что показывает колокольчик (без событий переписки)
    static func visible(_ items: [AppNotification]) -> [AppNotification] {
        items.filter { $0.type.showsInBell }
    }

    /// «Сегодня», «Вчера», «13 октября» или «13 октября 2025 г.», если это другой год
    static func dayTitle(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Сегодня" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return "Вчера" }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        return sameYear ? AppDate.dayLong(day) : AppDate.dayLongYear(day)
    }

    /// Время «назад»: «только что», «5 мин назад», «3 ч назад», «2 дн назад»; дальше — дата
    static func timeAgo(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "только что" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) мин назад" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) ч назад" }
        let days = hours / 24
        if days < 7 { return "\(days) дн назад" }
        return AppDate.dayShort(date)
    }
}
