import Foundation

// MARK: - MeetingDefaults
// Что подставить в форму новой заявки. Чистая логика без SwiftUI — проверяется тестами.
enum MeetingDefaults {

    struct Slot: Equatable {
        let day: Date      // начало дня
        let start: Date    // дата и время начала
        let end: Date      // дата и время конца
    }

    /// Последнее время начала по умолчанию: игра на два часа должна закончиться до 23:30
    static let latestDefaultStartMinutes = 21 * 60 + 30
    static let defaultDurationMinutes = 120
    static let leadMinutes = 60
    static let roundToMinutes = 30
    /// Если сегодня уже поздно — предлагаем завтра в это время
    static let tomorrowStartHour = 18

    /// Сегодня, начало не раньше чем через час, округлено вверх до получаса.
    /// Поздним вечером — завтра с 18:00 до 20:00.
    static func initialSlot(now: Date = Date(), calendar: Calendar = .current) -> Slot {
        let today = calendar.startOfDay(for: now)
        let earliest = now.addingTimeInterval(TimeInterval(leadMinutes * 60))
        let start = roundedUp(earliest, toMinutes: roundToMinutes, calendar: calendar)

        let sameDay = calendar.isDate(start, inSameDayAs: today)
        let minutes = minutesFromMidnight(start, calendar: calendar)

        if sameDay && minutes <= latestDefaultStartMinutes {
            return Slot(day: today,
                        start: start,
                        end: start.addingTimeInterval(TimeInterval(defaultDurationMinutes * 60)))
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let tomorrowStart = calendar.date(bySettingHour: tomorrowStartHour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        return Slot(day: tomorrow,
                    start: tomorrowStart,
                    end: tomorrowStart.addingTimeInterval(TimeInterval(defaultDurationMinutes * 60)))
    }

    /// День из одного значения + часы и минуты из другого
    static func combine(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let t = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    /// Начало игры уже позади (с запасом в одну минуту, чтобы не мигало на границе)
    static func startsInPast(day: Date, start: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        combine(day: day, time: start, calendar: calendar) < now.addingTimeInterval(-60)
    }

    // MARK: Внутри

    private static func minutesFromMidnight(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private static func roundedUp(_ date: Date, toMinutes step: Int, calendar: Calendar) -> Date {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let total = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let rounded = ((total + step - 1) / step) * step
        let base = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? date
        return calendar.date(byAdding: .minute, value: rounded, to: base) ?? date
    }
}
