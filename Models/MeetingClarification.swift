import Foundation
import FirebaseFirestore

// MARK: - Чтение дат из документа
// Firestore отдаёт `Timestamp`, тесты передают обычную `Date`: так тестам не нужен Firebase.
enum DocumentValue {
    static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        return value as? Date
    }
}

// MARK: - Тип действия
// Предложения (подтвердить, другое время, место, отменить) ждут ответа партнёра.
// Сообщение и быстрые статусы («опаздываю», «на месте») ответа не требуют.
enum MeetingActionType: String {
    case confirm         = "confirm"          // Подтверждаю встречу
    case suggestTime     = "suggest_time"     // Предлагаю другое время
    case suggestLocation = "suggest_location" // Предлагаю другое место
    case cancelRequest   = "cancel_request"   // Хочу отменить встречу
    case message         = "message"          // Короткое сообщение
    case late            = "late"             // Опаздываю на N минут
    case arrived         = "arrived"          // Я на месте

    /// Партнёр должен принять или отклонить
    var needsResponse: Bool {
        switch self {
        case .confirm, .suggestTime, .suggestLocation, .cancelRequest: return true
        case .message, .late, .arrived:                                return false
        }
    }
}

enum MeetingActionStatus: String {
    case pending  = "pending"
    case accepted = "accepted"
    case declined = "declined"
    case info     = "info"       // сообщение без ответа
}

// MARK: - Уточнение по встрече
struct MeetingClarification: Identifiable {
    let id: String
    let sparringRequestId: String
    let authorId: String
    let authorName: String
    let bookedById: String
    let bookedByName: String
    let sparringDate: Date
    let sparringTimeSlot: String
    let sparringCity: String
    let sparringLocation: String
    let sparringLatitude: Double?
    let sparringLongitude: Double?
    let status: String
    let updatedAt: Date

    // Последнее событие и прочитанность (как в мессенджерах)
    let lastActionAt: Date?
    let lastActionBy: String
    let lastActionText: String
    let unread: [String: Int]          // userId → сколько событий он не видел
    let readAt: [String: Date]         // userId → когда последний раз открывал диалог

    // Имя партнёра относительно текущего пользователя
    func partnerName(currentUserId: String) -> String {
        currentUserId == authorId ? bookedByName : authorName
    }

    func partnerId(currentUserId: String) -> String {
        currentUserId == authorId ? bookedById : authorId
    }

    func unreadCount(for userId: String) -> Int {
        max(unread[userId] ?? 0, 0)
    }

    /// Когда была последняя активность: для сортировки и подписи в списке
    var activityDate: Date { lastActionAt ?? updatedAt }

    var hasCoordinates: Bool { sparringLatitude != nil && sparringLongitude != nil }

    init?(id: String, data: [String: Any]) {
        guard
            let sparringRequestId = data["sparringRequestId"] as? String,
            let authorId          = data["authorId"]          as? String,
            let bookedById        = data["bookedById"]        as? String,
            let sparringDate      = DocumentValue.date(data["sparringDate"])
        else { return nil }

        self.id                  = id
        self.sparringRequestId   = sparringRequestId
        self.authorId            = authorId
        self.authorName          = data["authorName"]       as? String ?? ""
        self.bookedById          = bookedById
        self.bookedByName        = data["bookedByName"]     as? String ?? ""
        self.sparringDate        = sparringDate
        self.sparringTimeSlot    = data["sparringTimeSlot"] as? String ?? ""
        self.sparringCity        = data["sparringCity"]     as? String ?? ""
        self.sparringLocation    = data["sparringLocation"] as? String ?? ""
        self.sparringLatitude    = data["sparringLatitude"]  as? Double
        self.sparringLongitude   = data["sparringLongitude"] as? Double
        self.status              = data["status"]           as? String ?? "active"
        self.updatedAt           = DocumentValue.date(data["updatedAt"]) ?? Date()

        self.lastActionAt        = DocumentValue.date(data["lastActionAt"])
        self.lastActionBy        = data["lastActionBy"]   as? String ?? ""
        self.lastActionText      = data["lastActionText"] as? String ?? ""

        var unread: [String: Int] = [:]
        for (key, value) in data["unread"] as? [String: Any] ?? [:] {
            if let number = value as? Int { unread[key] = number }
        }
        self.unread = unread

        var readAt: [String: Date] = [:]
        for (key, value) in data["readAt"] as? [String: Any] ?? [:] {
            if let date = DocumentValue.date(value) { readAt[key] = date }
        }
        self.readAt = readAt
    }
}

// Для навигации по значению (NavigationStack(path:)): диалог определяется по id
extension MeetingClarification: Hashable {
    static func == (lhs: MeetingClarification, rhs: MeetingClarification) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Действие в уточнении
struct MeetingAction: Identifiable {
    let id: String
    let clarificationId: String
    let fromUserId: String
    let fromUserName: String
    let type: MeetingActionType
    let proposedValue: String
    let status: MeetingActionStatus
    let createdAt: Date

    // Необязательные данные предложения
    let latitude: Double?
    let longitude: Double?
    let note: String
    let proposedDate: Date?        // новый день встречи (для «другое время»)

    var hasCoordinates: Bool { latitude != nil && longitude != nil }

    /// «19 октября, 20:00 – 22:00»; без даты, если день не менялся
    func timeText(calendar: Calendar = .current) -> String {
        if let day = proposedDate {
            return "\(ChatTime.dayMonthFull(day, calendar: calendar)), \(proposedValue)"
        }
        return proposedValue
    }

    var typeLabel: String {
        switch type {
        case .confirm:         return "Подтверждаю встречу"
        case .suggestTime:     return "Предлагаю другое время"
        case .suggestLocation: return "Предлагаю место"
        case .cancelRequest:   return "Предлагаю отменить встречу"
        case .message:         return proposedValue
        case .late:            return "Опаздываю"
        case .arrived:         return "Я на месте"
        }
    }

    var statusLabel: String {
        switch status {
        case .pending:  return "Ожидает ответа"
        case .accepted: return "Принято"
        case .declined: return "Отклонено"
        case .info:     return ""
        }
    }

    init?(id: String, data: [String: Any]) {
        guard
            let clarificationId = data["clarificationId"] as? String,
            let fromUserId      = data["fromUserId"]      as? String,
            let typeStr         = data["type"]            as? String,
            let statusStr       = data["status"]          as? String,
            let type            = MeetingActionType(rawValue: typeStr),
            let status          = MeetingActionStatus(rawValue: statusStr),
            let createdAt       = DocumentValue.date(data["createdAt"])
        else { return nil }

        self.id              = id
        self.clarificationId = clarificationId
        self.fromUserId      = fromUserId
        self.fromUserName    = data["fromUserName"]   as? String ?? ""
        self.type            = type
        self.proposedValue   = data["proposedValue"]  as? String ?? ""
        self.status          = status
        self.createdAt       = createdAt
        self.latitude        = data["latitude"]       as? Double
        self.longitude       = data["longitude"]      as? Double
        self.note            = data["note"]           as? String ?? ""
        self.proposedDate    = DocumentValue.date(data["proposedDate"])
    }
}

// MARK: - Действие, которое собираемся отправить
struct OutgoingAction {
    var type: MeetingActionType
    var value: String = ""
    var latitude: Double? = nil
    var longitude: Double? = nil
    var note: String = ""
    var proposedDate: Date? = nil

    var status: MeetingActionStatus {
        type.needsResponse ? .pending : .info
    }

    /// Короткий текст для списка диалогов
    func previewText(calendar: Calendar = .current) -> String {
        switch type {
        case .confirm:
            return "Подтверждаю встречу"
        case .suggestTime:
            return "Другое время: \(timeDescription(calendar: calendar))"
        case .suggestLocation:
            return "Место: \(value)"
        case .cancelRequest:
            return "Предлагаю отменить встречу"
        case .message:
            return NotificationTexts.shortened(value, limit: 80)
        case .late:
            return "Опаздываю на \(value) мин"
        case .arrived:
            return "Я на месте"
        }
    }

    /// «19 октября, 19:00 – 21:00»; без даты, если день не менялся
    func timeDescription(calendar: Calendar = .current) -> String {
        if let day = proposedDate {
            return "\(ChatTime.dayMonthFull(day, calendar: calendar)), \(value)"
        }
        return value
    }

    /// Что показать в уведомлении партнёру
    var notificationKind: NotificationTexts.ClarificationKind {
        switch type {
        case .confirm:         return .confirm
        case .suggestTime:     return .time(timeDescription())
        case .suggestLocation: return .place(value)
        case .cancelRequest:   return .cancel
        case .message:         return .message(value)
        case .late:            return .late(minutes: Int(value) ?? 0)
        case .arrived:         return .arrived
        }
    }
}
