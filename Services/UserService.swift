import Foundation
import FirebaseFirestore

// MARK: - UserService
// Работа с профилями пользователей: чтение, сохранение и обновление
// денормализованных копий данных автора. Все колбэки приходят на главной очереди.
final class UserService {

    static let shared = UserService()

    private let db = Firestore.firestore()

    /// Firestore принимает в одном запросе `in` не больше 30 значений
    private static let batchSize = 30

    /// Имена, которые уже спрашивали: на пять минут хватает — имя меняют редко,
    /// а свои правки профиля сбрасывают запись (см. `updateProfile`)
    private var nameCache = TimedCache<String>(ttl: 300)

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
    /// Один запрос на каждые 30 человек (а не по запросу на человека), а уже известные имена
    /// берутся из памяти: имена партнёров в играх и матчах повторяются постоянно.
    func fetchNames(ids: [String], completion: @escaping ([String: String]) -> Void) {
        let uniqueIds = Set(ids).filter { !$0.isEmpty }
        var result: [String: String] = [:]
        var missing: [String] = []

        for id in uniqueIds {
            if let name = nameCache.value(for: id) {
                result[id] = name
            } else {
                missing.append(id)
            }
        }

        guard !missing.isEmpty else {
            completion(result)
            return
        }

        let group = DispatchGroup()
        for chunk in PartnerNames.chunks(missing, size: UserService.batchSize) {
            group.enter()
            db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments { [weak self] snapshot, _ in
                    DispatchQueue.main.async {
                        for doc in snapshot?.documents ?? [] {
                            let name = UserService.fullName(from: doc.data())
                            self?.nameCache.set(name, for: doc.documentID)
                            result[doc.documentID] = name
                        }
                        group.leave()
                    }
                }
        }

        group.notify(queue: .main) { completion(result) }
    }

    // MARK: - Запись

    func updateProfile(userId: String, fields: [String: Any], completion: @escaping (Error?) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwiseFailing: completion) else { return }
        nameCache.remove(userId)
        db.collection("users").document(userId).updateData(fields) { [weak self] error in
            DispatchQueue.main.async {
                self?.nameCache.remove(userId)
                completion(error)
            }
        }
    }

    /// Забыть запомненные имена (выход из аккаунта)
    func clearNameCache() {
        nameCache.removeAll()
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
