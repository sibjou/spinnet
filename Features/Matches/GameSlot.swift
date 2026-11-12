import Foundation

// MARK: - GameSlot
// Разбор строки времени заявки вида «18:00 – 20:00».
enum GameSlot {

    /// Начало и конец в минутах от полуночи. Если конец не позже начала,
    /// считаем, что игра перешла через полночь.
    static func minutes(from slot: String) -> (start: Int, end: Int)? {
        let normalized = slot
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
        let parts = normalized
            .split(separator: "-", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let start = minutesOfDay(parts[0]),
              let end   = minutesOfDay(parts[1]) else { return nil }
        return (start, end > start ? end : end + 24 * 60)
    }

    /// Длительность в минутах; 0, если слот не разобрался
    static func durationMinutes(of slot: String) -> Int {
        guard let range = minutes(from: slot) else { return 0 }
        return range.end - range.start
    }

    /// Момент начала игры в указанный день
    static func startDate(day: Date, slot: String, calendar: Calendar = .current) -> Date? {
        guard let range = minutes(from: slot) else { return nil }
        let midnight = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: range.start, to: midnight)
    }

    private static func minutesOfDay(_ text: String) -> Int? {
        let pieces = text.split(separator: ":")
        guard pieces.count == 2,
              let hours = Int(pieces[0]), let minutes = Int(pieces[1]),
              (0...23).contains(hours), (0...59).contains(minutes) else { return nil }
        return hours * 60 + minutes
    }
}
