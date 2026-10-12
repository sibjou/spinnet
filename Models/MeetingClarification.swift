import Foundation
import FirebaseFirestore

// MARK: - Тип действия (не свободный текст — соответствует закону)
enum MeetingActionType: String {
    case confirm         = "confirm"          // Подтверждаю встречу
    case suggestTime     = "suggest_time"     // Предлагаю другое время
    case suggestLocation = "suggest_location" // Предлагаю другое место
    case cancelRequest   = "cancel_request"   // Хочу отменить встречу
}

enum MeetingActionStatus: String {
    case pending  = "pending"
    case accepted = "accepted"
    case declined = "declined"
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
    let status: String
    let updatedAt: Date

    // Имя партнёра относительно текущего пользователя
    func partnerName(currentUserId: String) -> String {
        currentUserId == authorId ? bookedByName : authorName
    }

    func partnerId(currentUserId: String) -> String {
        currentUserId == authorId ? bookedById : authorId
    }

    init?(id: String, data: [String: Any]) {
        guard
            let sparringRequestId = data["sparringRequestId"] as? String,
            let authorId          = data["authorId"]          as? String,
            let bookedById        = data["bookedById"]        as? String,
            let dateTs            = data["sparringDate"]      as? Timestamp
        else { return nil }

        self.id                  = id
        self.sparringRequestId   = sparringRequestId
        self.authorId            = authorId
        self.authorName          = data["authorName"]       as? String ?? ""
        self.bookedById          = bookedById
        self.bookedByName        = data["bookedByName"]     as? String ?? ""
        self.sparringDate        = dateTs.dateValue()
        self.sparringTimeSlot    = data["sparringTimeSlot"] as? String ?? ""
        self.sparringCity        = data["sparringCity"]     as? String ?? ""
        self.sparringLocation    = data["sparringLocation"] as? String ?? ""
        self.status              = data["status"]           as? String ?? "active"
        self.updatedAt           = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
    }
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

    var typeLabel: String {
        switch type {
        case .confirm:         return "Подтверждаю встречу"
        case .suggestTime:     return "Предлагаю другое время"
        case .suggestLocation: return "Предлагаю другое место"
        case .cancelRequest:   return "Предлагаю отменить встречу"
        }
    }

    var statusLabel: String {
        switch status {
        case .pending:  return "Ожидает ответа"
        case .accepted: return "Принято"
        case .declined: return "Отклонено"
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
            let createdAt       = (data["createdAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id              = id
        self.clarificationId = clarificationId
        self.fromUserId      = fromUserId
        self.fromUserName    = data["fromUserName"]   as? String ?? ""
        self.type            = type
        self.proposedValue   = data["proposedValue"]  as? String ?? ""
        self.status          = status
        self.createdAt       = createdAt
    }
}
