import Foundation

// MARK: - Текст уведомления
struct NotificationCopy: Equatable {
    let title: String
    let body: String
}

// MARK: - Тексты уведомлений
// Чистые функции без Firebase и SwiftUI: их проверяют тесты.
// Во всех текстах называется человек, который сделал действие, и сама встреча.
enum NotificationTexts {

    /// «19 октября, 18:00 – 20:00»; пустые части пропускаются
    static func when(dateText: String, slot: String) -> String {
        [dateText, slot]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private static func person(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Партнёр" : trimmed
    }

    private static func suffix(_ when: String) -> String {
        when.isEmpty ? "" : " \(when)"
    }

    // MARK: Отмена

    /// `byAuthor` — отменил автор заявки: игра закрывается.
    /// Иначе отказался партнёр: заявка автора снова в ленте.
    static func cancellation(name: String, byAuthor: Bool, when: String) -> NotificationCopy {
        let who = person(name)
        if byAuthor {
            return NotificationCopy(
                title: "Игра отменена",
                body: "\(who) отменил(а) игру\(suffix(when)). Заявка закрыта — выберите другую в ленте"
            )
        }
        return NotificationCopy(
            title: "Партнёр отказался от игры",
            body: "\(who) отказался(ась) от игры\(suffix(when)). Ваша заявка снова в ленте"
        )
    }

    // MARK: Уточнения

    /// Что именно предложил или написал партнёр
    enum ClarificationKind: Equatable {
        case confirm
        case time(String)
        case place(String)
        case cancel
        case message(String)
        case late(minutes: Int)
        case arrived
    }

    static func clarification(from name: String, kind: ClarificationKind) -> NotificationCopy {
        let who = person(name)
        switch kind {
        case .confirm:
            return NotificationCopy(title: "\(who) подтверждает встречу", body: "Всё в силе — детали в уточнениях")
        case .time(let value):
            return NotificationCopy(title: "\(who) предлагает другое время", body: value)
        case .place(let value):
            return NotificationCopy(title: "\(who) предлагает место", body: value)
        case .cancel:
            return NotificationCopy(title: "\(who) предлагает отменить встречу", body: "Откройте уточнение и ответьте")
        case .message(let text):
            return NotificationCopy(title: who, body: shortened(text, limit: 120))
        case .late(let minutes):
            return NotificationCopy(title: "\(who) опаздывает", body: "Примерно на \(minutes) мин")
        case .arrived:
            return NotificationCopy(title: "\(who) уже на месте", body: "Можно начинать")
        }
    }

    /// Партнёр ответил на предложение
    static func response(from name: String, accepted: Bool, summary: String) -> NotificationCopy {
        let who = person(name)
        return NotificationCopy(
            title: accepted ? "\(who) принимает предложение" : "\(who) отклоняет предложение",
            body: summary
        )
    }

    /// Обрезает длинный текст для строки уведомления
    static func shortened(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)) + "…"
    }
}
