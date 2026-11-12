import Foundation
import FirebaseFirestore

// MARK: - AppNotification
// Модель внутри-приложения уведомления
// Сохраняется в Firestore в подколлекции notifications/{userId}/items/

enum NotificationType: String, CaseIterable {
    case gameReminder       = "game_reminder"        // Скоро игра
    case reviewReminder     = "review_reminder"      // Оцените игру
    case cancellation       = "cancellation"          // Партнёр отменил
    case requestBooked      = "request_booked"        // Вашу заявку забронировали
    case revisionRequest    = "revision_request"     // Модератор просит правку
    case tournamentStarting = "tournament_starting"   // Турнир скоро начнётся
    case matchProposed      = "match_proposed"        // Партнёр внёс счёт игры
    case matchCountered     = "match_countered"       // Партнёр предложил другой счёт
    case matchConfirmed     = "match_confirmed"       // Счёт подтверждён
    case matchDisputed      = "match_disputed"        // Счёт оспорен
    case matchReminder      = "match_reminder"        // Внесите счёт игры
    case clarification      = "clarification"         // Новое в уточнении встречи

    var icon: String {
        switch self {
        case .gameReminder:       return "figure.table.tennis"
        case .reviewReminder:     return "star.fill"
        case .cancellation:       return "xmark.circle.fill"
        case .requestBooked:      return "person.fill.checkmark"
        case .revisionRequest:    return "pencil.circle.fill"
        case .tournamentStarting: return "trophy.fill"
        case .matchProposed:      return "list.clipboard.fill"
        case .matchCountered:     return "arrow.left.arrow.right.circle.fill"
        case .matchConfirmed:     return "checkmark.seal.fill"
        case .matchDisputed:      return "exclamationmark.triangle.fill"
        case .matchReminder:      return "list.clipboard.fill"
        case .clarification:      return "bubble.left.and.bubble.right.fill"
        }
    }

    var iconColor: String {
        switch self {
        case .gameReminder:       return "primary"
        case .reviewReminder:     return "star"
        case .cancellation:       return "danger"
        case .requestBooked:      return "info"
        case .revisionRequest:    return "warning"
        case .tournamentStarting: return "primary"
        case .matchProposed, .matchCountered, .matchReminder: return "primary"
        case .clarification:      return "primary"
        case .matchConfirmed:     return "success"
        case .matchDisputed:      return "warning"
        }
    }

    /// Раздел для фильтра в центре уведомлений
    var category: NotificationCategory {
        switch self {
        case .gameReminder:       return .games
        case .reviewReminder:     return .reviews
        case .cancellation:       return .cancellations
        case .requestBooked:      return .bookings
        case .revisionRequest:    return .moderation
        case .tournamentStarting: return .tournaments
        case .matchProposed, .matchCountered, .matchConfirmed, .matchDisputed, .matchReminder:
            return .scores
        case .clarification:      return .clarifications
        }
    }

    var displayName: String { category.displayName }

    /// Уведомление ведёт на экран счёта матча
    var opensMatch: Bool {
        switch self {
        case .matchProposed, .matchCountered, .matchConfirmed, .matchDisputed, .matchReminder: return true
        default: return false
        }
    }

    /// Уведомление ведёт на экран игры
    var opensGame: Bool {
        switch self {
        case .gameReminder, .reviewReminder, .requestBooked: return true
        default: return opensMatch
        }
    }

    /// Уведомление ведёт сразу на форму отзыва
    var opensReview: Bool { self == .reviewReminder }

    /// Уведомление ведёт в профиль человека (targetId — его id)
    var opensProfile: Bool { self == .cancellation }

    /// Уведомление ведёт в диалог уточнения (targetId — id диалога)
    var opensClarification: Bool { self == .clarification }

    /// Показывается в «Уведомлениях» и считается на колокольчике.
    /// События переписки живут во вкладке «Чаты» со своим значком: дважды их показывать не нужно.
    var showsInBell: Bool { self != .clarification }

    /// Значения `type`, которые считает колокольчик (для запросов к базе)
    static var bellRawValues: [String] {
        allCases.filter(\.showsInBell).map(\.rawValue)
    }
}

// MARK: - Разделы фильтра
enum NotificationCategory: String {
    case games, reviews, cancellations, bookings, moderation, tournaments, scores, clarifications

    var displayName: String {
        switch self {
        case .games:         return "Игры"
        case .reviews:       return "Отзывы"
        case .cancellations: return "Отмены"
        case .bookings:      return "Бронирования"
        case .moderation:    return "Модерация"
        case .tournaments:   return "Турниры"
        case .scores:        return "Счёт"
        case .clarifications: return "Уточнения"
        }
    }
}

struct AppNotification: Identifiable {
    let id: String
    let type: NotificationType
    let title: String
    let body: String
    let targetType: String?    // "game" / "tournament" / "review" / "profile" / "clarification"
    let targetId: String?      // ID связанного объекта
    let actorId: String?       // кто совершил действие (для аватара в списке)
    let actorName: String?
    let isRead: Bool
    let createdAt: Date

    init?(id: String, data: [String: Any]) {
        guard
            let typeStr = data["type"] as? String,
            let type    = NotificationType(rawValue: typeStr),
            let title   = data["title"] as? String,
            let body    = data["body"]  as? String,
            let createdAt = DocumentValue.date(data["createdAt"])
        else { return nil }

        self.id         = id
        self.type       = type
        self.title      = title
        self.body       = body
        self.targetType = data["targetType"] as? String
        self.targetId   = data["targetId"]   as? String
        self.actorId    = data["actorId"]    as? String
        self.actorName  = data["actorName"]  as? String
        self.isRead     = data["isRead"]     as? Bool ?? false
        self.createdAt  = createdAt
    }
}
