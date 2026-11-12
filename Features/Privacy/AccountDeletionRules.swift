import Foundation

// MARK: - Удаление аккаунта: тексты и правила
// Магазин приложений требует, чтобы аккаунт можно было удалить из самого приложения.
// Сам порядок удаления — в AccountDeletionService; здесь то, что можно проверить без сети.

enum AccountDeletionRules {

    /// Под этим именем остаются заявки и отзывы удалившего аккаунт
    static let anonymousName = "Удалённый пользователь"

    /// Что произойдёт: показывается человеку до подтверждения
    static let consequences: [String] = [
        "Профиль, имя и город удалятся без возможности восстановления.",
        "Заявки без ответа удалятся, назначенные игры отменятся — партнёры получат уведомление.",
        "Сыгранные матчи и отзывы останутся у других игроков, но без вашего имени.",
        "Сообщения, которые вы отправили в чатах, могут остаться у собеседников."
    ]

    /// Понятный текст по коду ошибки входа (Firebase Auth)
    static func message(forAuthErrorCode code: Int) -> String {
        switch code {
        case 17009, 17004: return "Неверный пароль"
        case 17010:        return "Слишком много попыток. Попробуйте позже"
        case 17020:        return "Нет подключения к интернету"
        case 17014:        return "Нужно войти заново: выйдите из аккаунта, войдите и повторите"
        default:           return "Не удалось удалить аккаунт. Попробуйте ещё раз"
        }
    }

    /// Пока человек организует турниры, аккаунт не удаляется: участники остались бы без организатора
    static func blockedByTournaments(count: Int) -> String {
        "Сначала завершите или удалите турниры, которые вы организуете: \(count) \(tournamentsWord(count))."
    }

    static func tournamentsWord(_ count: Int) -> String {
        let mod10 = count % 10, mod100 = count % 100
        if mod100 >= 11 && mod100 <= 14 { return "турниров" }
        switch mod10 {
        case 1:       return "турнир"
        case 2, 3, 4: return "турнира"
        default:      return "турниров"
        }
    }

    /// Турнир, который ещё не закончился
    static func isOpenTournament(status: String) -> Bool {
        status == "upcoming" || status == "in_progress"
    }

    /// Кнопка удаления нажимается, когда введён пароль
    static func canSubmit(password: String) -> Bool {
        !password.isEmpty
    }
}
