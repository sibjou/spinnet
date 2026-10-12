import Foundation
import FirebaseFirestore

// MARK: - AppNotification
// Модель внутри-приложения уведомления
// Сохраняется в Firestore в подколлекции notifications/{userId}/items/

enum NotificationType: String {
    case gameReminder       = "game_reminder"        // Скоро игра
    case reviewReminder     = "review_reminder"      // Оцените игру
    case cancellation       = "cancellation"          // Партнёр отменил
    case requestBooked      = "request_booked"        // Вашу заявку забронировали
    case revisionRequest    = "revision_request"     // Модератор просит правку
    case tournamentStarting = "tournament_starting"   // Турнир скоро начнётся

    var icon: String {
        switch self {
        case .gameReminder:       return "figure.table.tennis"
        case .reviewReminder:     return "star.fill"
        case .cancellation:       return "xmark.circle.fill"
        case .requestBooked:      return "person.fill.checkmark"
        case .revisionRequest:    return "pencil.circle.fill"
        case .tournamentStarting: return "trophy.fill"
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
        }
    }

    var displayName: String {
        switch self {
        case .gameReminder:       return "Игры"
        case .reviewReminder:     return "Отзывы"
        case .cancellation:       return "Отмены"
        case .requestBooked:      return "Бронирования"
        case .revisionRequest:    return "Модерация"
        case .tournamentStarting: return "Турниры"
        }
    }
}

struct AppNotification: Identifiable {
    let id: String
    let type: NotificationType
    let title: String
    let body: String
    let targetType: String?    // "game" / "tournament" / "review"
    let targetId: String?      // ID связанного объекта
    let isRead: Bool
    let createdAt: Date

    init?(id: String, data: [String: Any]) {
        guard
            let typeStr = data["type"] as? String,
            let type    = NotificationType(rawValue: typeStr),
            let title   = data["title"] as? String,
            let body    = data["body"]  as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id         = id
        self.type       = type
        self.title      = title
        self.body       = body
        self.targetType = data["targetType"] as? String
        self.targetId   = data["targetId"]   as? String
        self.isRead     = data["isRead"]     as? Bool ?? false
        self.createdAt  = createdAt
    }
}
