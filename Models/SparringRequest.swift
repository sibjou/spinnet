import Foundation
import FirebaseFirestore

struct SparringRequest: Identifiable, Equatable {
    let id: String

    // Автор (денормализованные данные — не нужны отдельные запросы в users)
    let userId: String
    let authorFirstName: String
    let authorLastName: String
    let authorSkillLevel: String
    let authorGrip: String
    let authorPlayStyle: String

    // Детали встречи
    let date: Date
    let timeSlot: String
    let city: String
    let location: String
    let desiredLevel: String

    // Статус и участники
    let status: String
    let bookedBy: String?
    let bookedAt: Date?
    let confirmedBy: [String]
    let createdAt: Date

    var authorFullName: String {
        "\(authorFirstName) \(authorLastName)".trimmingCharacters(in: .whitespaces)
    }

    static func == (lhs: SparringRequest, rhs: SparringRequest) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
    }

    // Возвращает nil если документ Firestore некорректный
    init?(id: String, data: [String: Any]) {
        guard
            let userId    = data["userId"]   as? String,
            let dateTs    = data["date"]      as? Timestamp,
            let timeSlot  = data["timeSlot"]  as? String,
            let location  = data["location"]  as? String,
            let status    = data["status"]    as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id               = id
        self.userId           = userId
        self.authorFirstName  = data["authorFirstName"]  as? String ?? ""
        self.authorLastName   = data["authorLastName"]   as? String ?? ""
        self.authorSkillLevel = data["authorSkillLevel"] as? String ?? ""
        self.authorGrip       = data["authorGrip"]       as? String ?? ""
        self.authorPlayStyle  = data["authorPlayStyle"]  as? String ?? ""
        self.date             = dateTs.dateValue()
        self.timeSlot         = timeSlot
        self.city             = data["city"]             as? String ?? ""
        self.location         = location
        self.desiredLevel     = data["desiredLevel"]     as? String ?? "Любой"
        self.status           = status
        self.bookedBy         = data["bookedBy"]         as? String
        self.bookedAt         = (data["bookedAt"]        as? Timestamp)?.dateValue()
        self.confirmedBy      = data["confirmedBy"]      as? [String] ?? []
        self.createdAt        = createdAt
    }
}
