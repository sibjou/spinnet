import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - SparringService
// Отвечает за работу с заявками на спарринг:
// загрузка моих заявок, забронированных, истории игр
class SparringService: ObservableObject {
    
    @Published var myActiveRequests: [[String: Any]] = []    // Мои активные заявки
    @Published var myBookedGames: [[String: Any]] = []       // Игры где я забронировал или меня забронировали
    @Published var myCompletedGames: [[String: Any]] = []    // Завершённые игры (история)
    @Published var isLoading = false
    
    private let db = Firestore.firestore()
    
    // MARK: - Загрузка моих активных заявок
    // Заявки которые я создал и которые ещё никто не забронировал
    func loadMyActiveRequests(userId: String) {
        db.collection("sparring_requests")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", isEqualTo: "active")
            .getDocuments { [weak self] snapshot, _ in
                DispatchQueue.main.async {
                    self?.myActiveRequests = snapshot?.documents.map { doc in
                        var data = doc.data()
                        data["documentId"] = doc.documentID
                        return data
                    } ?? []
                }
            }
    }
    
    // MARK: - Загрузка забронированных игр
    // Игры где я автор заявки ИЛИ я забронировал чужую заявку
    func loadMyBookedGames(userId: String) {
        // Загружаю заявки которые я создал и кто-то забронировал
        db.collection("sparring_requests")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", isEqualTo: "booked")
            .getDocuments { [weak self] snapshot, _ in
                DispatchQueue.main.async {
                    var games: [[String: Any]] = snapshot?.documents.map { doc in
                        var data = doc.data()
                        data["documentId"] = doc.documentID
                        data["myRole"] = "автор"  // Я создал эту заявку
                        return data
                    } ?? []
                    
                    // Также загружаю заявки которые я забронировал
                    self?.db.collection("sparring_requests")
                        .whereField("bookedBy", isEqualTo: userId)
                        .whereField("status", isEqualTo: "booked")
                        .getDocuments { snapshot2, _ in
                            DispatchQueue.main.async {
                                let bookedByMe: [[String: Any]] = snapshot2?.documents.map { doc in
                                    var data = doc.data()
                                    data["documentId"] = doc.documentID
                                    data["myRole"] = "партнёр"  // Я откликнулся
                                    return data
                                } ?? []
                                
                                games.append(contentsOf: bookedByMe)
                                self?.myBookedGames = games
                            }
                        }
                }
            }
    }
    
    // MARK: - Загрузка истории завершённых игр
    func loadMyCompletedGames(userId: String) {
        // Игры где я автор
        db.collection("sparring_requests")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", isEqualTo: "completed")
            .getDocuments { [weak self] snapshot, _ in
                DispatchQueue.main.async {
                    var games: [[String: Any]] = snapshot?.documents.map { doc in
                        var data = doc.data()
                        data["documentId"] = doc.documentID
                        return data
                    } ?? []
                    
                    // Игры где я партнёр
                    self?.db.collection("sparring_requests")
                        .whereField("bookedBy", isEqualTo: userId)
                        .whereField("status", isEqualTo: "completed")
                        .getDocuments { snapshot2, _ in
                            DispatchQueue.main.async {
                                let completedByMe: [[String: Any]] = snapshot2?.documents.map { doc in
                                    var data = doc.data()
                                    data["documentId"] = doc.documentID
                                    return data
                                } ?? []
                                
                                games.append(contentsOf: completedByMe)
                                self?.myCompletedGames = games
                            }
                        }
                }
            }
    }
    
    // MARK: - Подтвердить что встреча состоялась
    // Оба участника подтверждают → статус меняется на completed
    func confirmMeeting(requestId: String, userId: String, completion: @escaping (Bool) -> Void) {
        let docRef = db.collection("sparring_requests").document(requestId)
        
        docRef.getDocument { doc, _ in
            guard let data = doc?.data() else {
                completion(false)
                return
            }
            
            // Добавляю ID подтвердившего в массив confirmedBy
            var confirmedBy = data["confirmedBy"] as? [String] ?? []
            if !confirmedBy.contains(userId) {
                confirmedBy.append(userId)
            }
            
            // Если оба подтвердили — статус "completed"
            var updateData: [String: Any] = ["confirmedBy": confirmedBy]
            if confirmedBy.count >= 2 {
                updateData["status"] = "completed"
                updateData["completedAt"] = Timestamp()
            }
            
            docRef.updateData(updateData) { error in
                DispatchQueue.main.async {
                    completion(error == nil)
                }
            }
        }
    }
    
    // MARK: - Загрузить все мои данные разом
    func loadAll(userId: String) {
        isLoading = true
        loadMyActiveRequests(userId: userId)
        loadMyBookedGames(userId: userId)
        loadMyCompletedGames(userId: userId)
        // Небольшая задержка чтобы все запросы успели завершиться
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isLoading = false
        }
    }
}
