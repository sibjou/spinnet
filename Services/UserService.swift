import Foundation
import FirebaseFirestore

// MARK: - UserService
// Работа с профилями пользователей: чтение, сохранение и обновление
// денормализованных копий данных автора. Все колбэки приходят на главной очереди.
final class UserService {

    static let shared = UserService()

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Чтение

    /// Данные профиля. `nil` — документа нет (например, аккаунт удалён).
    func fetchUser(id: String, completion: @escaping ([String: Any]?) -> Void) {
        db.collection("users").document(id).getDocument { doc, _ in
            DispatchQueue.main.async { completion(doc?.data()) }
        }
    }

    /// «Имя Фамилия» из данных профиля
    static func fullName(from data: [String: Any]) -> String {
        let first = data["firstName"] as? String ?? ""
        let last  = data["lastName"]  as? String ?? ""
        return "\(first) \(last)".trimmingCharacters(in: .whitespaces)
    }

    /// Имена нескольких пользователей: id → «Имя Фамилия».
    /// Пользователей без документа в результате нет.
    func fetchNames(ids: [String], completion: @escaping ([String: String]) -> Void) {
        let uniqueIds = Array(Set(ids))
        guard !uniqueIds.isEmpty else {
            completion([:])
            return
        }

        let group = DispatchGroup()
        var names: [String: String] = [:]

        for id in uniqueIds {
            group.enter()
            db.collection("users").document(id).getDocument { doc, _ in
                DispatchQueue.main.async {
                    if let data = doc?.data() {
                        names[id] = UserService.fullName(from: data)
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { completion(names) }
    }

    // MARK: - Запись

    func updateProfile(userId: String, fields: [String: Any], completion: @escaping (Error?) -> Void) {
        db.collection("users").document(userId).updateData(fields) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    /// Обновляет копии данных автора в активных заявках и предстоящих турнирах.
    /// История (завершённые игры) не трогается — хранит данные на момент игры.
    func updateDenormalizedAuthorData(userId: String,
                                      firstName: String,
                                      lastName: String,
                                      skillLevel: String,
                                      grip: String,
                                      playStyle: String,
                                      completion: @escaping () -> Void) {
        let group = DispatchGroup()

        group.enter()
        db.collection("sparring_requests")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", in: ["active", "booked", "in_progress"])
            .getDocuments { [db] snapshot, _ in
                guard let docs = snapshot?.documents, !docs.isEmpty else {
                    group.leave()
                    return
                }
                let batch = db.batch()
                for doc in docs {
                    batch.updateData([
                        "authorFirstName":  firstName,
                        "authorLastName":   lastName,
                        "authorSkillLevel": skillLevel,
                        "authorGrip":       grip,
                        "authorPlayStyle":  playStyle
                    ], forDocument: doc.reference)
                }
                batch.commit { _ in group.leave() }
            }

        group.enter()
        db.collection("tournaments")
            .whereField("organizerId", isEqualTo: userId)
            .whereField("status", in: ["upcoming", "in_progress"])
            .getDocuments { [db] snapshot, _ in
                guard let docs = snapshot?.documents, !docs.isEmpty else {
                    group.leave()
                    return
                }
                let batch = db.batch()
                for doc in docs {
                    batch.updateData([
                        "organizerName": "\(firstName) \(lastName)"
                    ], forDocument: doc.reference)
                }
                batch.commit { _ in group.leave() }
            }

        group.notify(queue: .main) { completion() }
    }
}
