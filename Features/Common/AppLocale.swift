import Foundation

// MARK: - AppLocale
// Язык интерфейса — тот, который iOS выбрала из переводов приложения.
// Сейчас в приложении только русский, поэтому всегда "ru". Когда появятся переводы
// (String Catalog + язык в Project → Info → Localizations), даты, месяцы и календарь
// сами переключатся на язык системы — править код не придётся.
enum AppLocale {

    /// Русский по умолчанию: если iOS ничего не выбрала (или выбрала служебную папку Base)
    static var current: Locale {
        let chosen = Bundle.main.preferredLocalizations.first { $0 != "Base" }
        return Locale(identifier: chosen ?? Bundle.main.developmentLocalization ?? "ru")
    }

    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = current
        return calendar
    }
}

// MARK: - AppDate
// Все даты на экранах — отсюда. Формат собирается по шаблону языка (setLocalizedDateFormatFromTemplate),
// поэтому порядок слов и падежи правильные в любом языке: «13 октября» / "October 13".
// Форматтеры дорогие в создании, поэтому хранятся в кэше и не создаются заново в каждой строке списка.
enum AppDate {

    /// «13 окт.»
    static func dayShort(_ date: Date) -> String { string(date, template: "dMMM") }

    /// «13 октября»
    static func dayLong(_ date: Date) -> String { string(date, template: "dMMMM") }

    /// «вторник, 13 октября»
    static func weekdayDayLong(_ date: Date) -> String { string(date, template: "EEEEdMMMM") }

    /// «13 октября 2026 г.»
    static func dayLongYear(_ date: Date) -> String { string(date, template: "dMMMMy") }

    /// «вторник, 13 октября 2026 г.»
    static func fullWithWeekday(_ date: Date) -> String { string(date, template: "EEEEdMMMMy") }

    /// «вт, 13 окт. 2026 г.» — для строки выбора даты
    static func shortWithWeekday(_ date: Date) -> String { string(date, template: "EEEdMMMy") }

    /// «13 окт. 2026 г., 18:30»
    static func dayShortYearTime(_ date: Date) -> String { string(date, template: "dMMMyHm") }

    /// «окт. 2026 г.»
    static func monthYear(_ date: Date) -> String { string(date, template: "LLLLy") }

    /// «18:30» — время игры хранится и показывается в 24-часовом виде одинаково на любом устройстве
    static func clock(_ date: Date) -> String {
        clockFormatter().string(from: date)
    }

    /// «18:30» → время в «нулевой» день; важны только часы и минуты
    static func parseClock(_ text: String) -> Date? {
        clockFormatter().date(from: text)
    }

    // MARK: Внутри

    private static func clockFormatter() -> DateFormatter {
        formatter(key: "clock|posix") {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "HH:mm"
            return f
        }
    }

    private static var cache: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    private static func string(_ date: Date, template: String) -> String {
        let locale = AppLocale.current
        return formatter(key: "\(locale.identifier)|\(template)") {
            let f = DateFormatter()
            f.locale = locale
            f.setLocalizedDateFormatFromTemplate(template)
            return f
        }.string(from: date)
    }

    private static func formatter(key: String, make: () -> DateFormatter) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let created = make()
        cache[key] = created
        return created
    }
}
