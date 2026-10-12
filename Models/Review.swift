import Foundation
import FirebaseFirestore

struct Review: Identifiable {
    let id: String
    let fromUserId: String
    let fromUserName: String
    let toUserId: String
    let sparringRequestId: String   // защита от дублей
    let rating: Int                  // 1-5
    let comment: String              // может быть пустым
    let createdAt: Date

    init?(id: String, data: [String: Any]) {
        guard
            let fromUserId       = data["fromUserId"]        as? String,
            let toUserId         = data["toUserId"]          as? String,
            let sparringRequestId = data["sparringRequestId"] as? String,
            let rating           = data["rating"]            as? Int,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        else { return nil }

        self.id                = id
        self.fromUserId        = fromUserId
        self.fromUserName      = data["fromUserName"] as? String ?? "Игрок"
        self.toUserId          = toUserId
        self.sparringRequestId = sparringRequestId
        self.rating            = rating
        self.comment           = data["comment"] as? String ?? ""
        self.createdAt         = createdAt
    }
}
