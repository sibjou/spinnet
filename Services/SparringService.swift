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
        db.collection("sparring_requests")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", in: ["booked", "in_progress"])
            .getDocuments { [weak self] snapshot, _ in
                    DispatchQueue.main.async {
                        var games: [[String: Any]] = snapshot?.documents.map { doc in
                            var data = doc.data()
                            data["documentId"] = doc.documentID
                            data["myRole"] = "автор"
                            // Партнёр — тот кто забронировал
                            data["partnerId"] = data["bookedBy"] as? String ?? ""
                            return data
                        } ?? []
                        
                        self?.db.collection("sparring_requests")
                            .whereField("bookedBy", isEqualTo: userId)
                            .whereField("status", in: ["booked", "in_progress"])
                            .getDocuments { snapshot2, _ in
                                DispatchQueue.main.async {
                                    let bookedByMe: [[String: Any]] = snapshot2?.documents.map { doc in
                                        var data = doc.data()
                                        data["documentId"] = doc.documentID
                                        data["myRole"] = "партнёр"
                                        // Партнёр — автор заявки
                                        data["partnerId"] = data["userId"] as? String ?? ""
                                        return data
                                    } ?? []
                                    
                                    games.append(contentsOf: bookedByMe)

                                    // Подгружаем имена партнёров
                                    self?.loadPartnerNames(games: games) { updatedGames in
                                        self?.myBookedGames = updatedGames
                                        // Планируем напоминания для всех забронированных игр на этом устройстве.
                                        // Благодаря одинаковому identifier повторный вызов перезаписывает, а не дублирует.
                                        self?.scheduleRemindersForGames(updatedGames)
                                    }
                                }
                            }
                    }
                }
        }
        
        // MARK: - Подгрузка имён партнёров к играм
        private func loadPartnerNames(games: [[String: Any]], completion: @escaping ([[String: Any]]) -> Void) {
            var updatedGames = games
            let group = DispatchGroup()
            
            for (index, game) in games.enumerated() {
                guard let partnerId = game["partnerId"] as? String, !partnerId.isEmpty else { continue }
                group.enter()
                
                db.collection("users").document(partnerId).getDocument { doc, _ in
                    if let data = doc?.data() {
                        let firstName = data["firstName"] as? String ?? ""
                        let lastName = data["lastName"] as? String ?? ""
                        updatedGames[index]["partnerName"] = "\(firstName) \(lastName)"
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                completion(updatedGames)
            }
        }
    
    // MARK: - Планирование напоминаний для забронированных игр
    // Вызывается при загрузке игр. Гарантирует что оба участника
    // (и автор, и партнёр) получат напоминания на своих устройствах,
    // так как каждый планирует у себя при открытии приложения.
    private func scheduleRemindersForGames(_ games: [[String: Any]]) {
        for game in games {
            // Планируем только для предстоящих игр (booked), не для идущих/завершённых
            guard (game["status"] as? String) == "booked",
                  let requestId = game["documentId"] as? String,
                  let dateTs = game["date"] as? Timestamp,
                  let timeSlot = game["timeSlot"] as? String else { continue }

            // Имя партнёра для текста уведомления
            let partnerName = game["partnerName"] as? String ?? "партнёром"

            let gameDate = dateTs.dateValue()

            NotificationService.shared.scheduleGameReminder(
                sparringRequestId: requestId,
                partnerName: partnerName,
                gameDate: gameDate,
                timeSlot: timeSlot
            )
            NotificationService.shared.scheduleReviewReminder(
                sparringRequestId: requestId,
                partnerName: partnerName,
                gameDate: gameDate,
                timeSlot: timeSlot
            )
        }
    }
    
    // MARK: - Загрузка истории завершённых игр
    func loadMyCompletedGames(userId: String) {
        db.collection("sparring_requests")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", in: ["completed", "expired"])
            .getDocuments { [weak self] snapshot, _ in
                DispatchQueue.main.async {
                    var games: [[String: Any]] = snapshot?.documents.map { doc in
                        var data = doc.data()
                        data["documentId"] = doc.documentID
                        data["partnerId"] = data["bookedBy"] as? String ?? ""
                        return data
                    } ?? []
                    
                    self?.db.collection("sparring_requests")
                        .whereField("bookedBy", isEqualTo: userId)
                        .whereField("status", in: ["completed", "expired"])
                        .getDocuments { snapshot2, _ in
                            DispatchQueue.main.async {
                                let completedByMe: [[String: Any]] = snapshot2?.documents.map { doc in
                                    var data = doc.data()
                                    data["documentId"] = doc.documentID
                                    data["partnerId"] = data["userId"] as? String ?? ""
                                    return data
                                } ?? []
                                
                                games.append(contentsOf: completedByMe)
                                
                                // Подгружаю имена партнёров
                                self?.loadPartnerNames(games: games) { updatedGames in
                                    self?.myCompletedGames = updatedGames
                                }
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
        // Завершённые НЕ загружаем — только по запросу
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isLoading = false
        }
    }
    
    // MARK: - Отмена бронирования
    // Когда один из участников отменяет — заявка возвращается в ленту
    // со статусом "active", bookedBy удаляется.
    // Уведомляем второго участника через систему уведомлений (Firestore + push)
    func cancelBooking(requestId: String, completion: @escaping (Bool) -> Void) {

        // Сначала получаем данные — нужны чтобы уведомить второго участника
        db.collection("sparring_requests").document(requestId).getDocument { [weak self] doc, _ in
            guard let data = doc?.data() else {
                completion(false)
                return
            }

            let authorId   = data["userId"]   as? String ?? ""
            let bookedById = data["bookedBy"] as? String ?? ""

            // Определяем кого уведомлять — того, кто НЕ отменяет
            let currentUserId = Auth.auth().currentUser?.uid ?? ""
            let notifyUserId  = (currentUserId == authorId) ? bookedById : authorId

            // Отменяем запланированные локальные уведомления
            NotificationService.shared.cancelGameNotifications(sparringRequestId: requestId)

            // Возвращаем заявку в ленту
            let updateData: [String: Any] = [
                "status":   "active",
                "bookedBy": FieldValue.delete(),
                "bookedAt": FieldValue.delete()
            ]

            self?.db.collection("sparring_requests").document(requestId).updateData(updateData) { error in
                DispatchQueue.main.async {
                    if error == nil && !notifyUserId.isEmpty {
                        // Уведомление второму участнику
                        NotificationService.shared.saveAndPush(
                            userId: notifyUserId,
                            type: .cancellation,
                            title: "Бронирование отменено",
                            body: "Партнёр отменил участие в игре. Оцените игрока — это поможет сообществу",
                            targetType: "game",
                            targetId: requestId
                        )
                    }
                    completion(error == nil)
                }
            }
        }
    }
    
    // MARK: - Подсчёт завершённых игр (без загрузки)
    // Используется для счётчика в свёрнутой секции истории
    @Published var completedGamesCount: Int = 0

    func loadCompletedGamesCount(userId: String) {
        var count1 = 0
        var count2 = 0
        let group = DispatchGroup()

        // Игры где я автор
        group.enter()
        db.collection("sparring_requests")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", in: ["completed", "expired"])
            .count
            .getAggregation(source: .server) { snapshot, _ in
                count1 = Int(truncating: snapshot?.count ?? 0)
                group.leave()
            }

        // Игры где я партнёр (бронировал)
        group.enter()
        db.collection("sparring_requests")
            .whereField("bookedBy", isEqualTo: userId)
            .whereField("status", in: ["completed", "expired"])
            .count
            .getAggregation(source: .server) { snapshot, _ in
                count2 = Int(truncating: snapshot?.count ?? 0)
                group.leave()
            }

        group.notify(queue: .main) { [weak self] in
            self?.completedGamesCount = count1 + count2
        }
    }
}
