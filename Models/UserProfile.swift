import Foundation
import FirebaseFirestore

struct UserProfile {
    let id: String
    let firstName: String
    let lastName: String
    let email: String
    let city: String
    let skillLevel: String
    let grip: String
    let playStyle: String
    let ratingLink: String
    let ttwRating: Int          // ← НОВОЕ
    let createdAt: Date

    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    init(id: String, data: [String: Any]) {
        self.id           = id
        self.firstName    = data["firstName"]  as? String ?? ""
        self.lastName     = data["lastName"]   as? String ?? ""
        self.email        = data["email"]      as? String ?? ""
        self.city         = data["city"]       as? String ?? ""
        self.skillLevel   = data["skillLevel"] as? String ?? ""
        self.grip         = data["grip"]       as? String ?? ""
        self.playStyle    = data["playStyle"]  as? String ?? ""
        self.ratingLink   = data["ratingLink"] as? String ?? ""
        self.ttwRating    = data["ttwRating"]  as? Int ?? 0     // ← НОВОЕ
        self.createdAt    = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
    }
}
