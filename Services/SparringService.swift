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
    func loadMyActiveRequests(userId: String, completion: (() -> Void)? = nil) {
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
                    completion?()
                }
            }
    }
    
    // MARK: - Загрузка забронированных игр
    // Игры где я автор заявки ИЛИ я забронировал чужую заявку
    func loadMyBookedGames(userId: String, completion: (() -> Void)? = nil) {
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
                        
                        let authorQueryLoaded = snapshot != nil

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

                                        // Игры, отменённые на другом устройстве, больше не напоминают о себе.
                                        // Чистим только когда оба запроса отработали: иначе сбой сети стёр бы живые напоминания
                                        if authorQueryLoaded, snapshot2 != nil {
                                            let ids = updatedGames.compactMap { $0["documentId"] as? String }
                                            NotificationService.shared.pruneGameReminders(keeping: Set(ids))
                                        }
                                        completion?()
                                    }
                                }
                            }
                    }
                }
        }
        
        // MARK: - Подгрузка имён партнёров к играм
        // Один запрос на каждые 30 разных партнёров, повторяющиеся имена берутся из памяти.
        // Раньше было по чтению документа на каждую игру: 200 игр с десятью партнёрами = 200 запросов.
        private func loadPartnerNames(games: [[String: Any]], completion: @escaping ([[String: Any]]) -> Void) {
            UserService.shared.fetchNames(ids: PartnerNames.ids(in: games)) { names in
                completion(PartnerNames.attach(names, to: games))
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
            // Напоминания после игры ставим только до её начала: во время игры и после
            // они уже стоят (или сработали), а внесённый счёт или отзыв их отменяет —
            // повторная постановка вернула бы то, что человек уже сделал
            if let start = GameSlot.startDate(day: gameDate, slot: timeSlot), start > Date() {
                NotificationService.shared.scheduleMatchReminder(
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
    
    // MARK: - Загрузить все мои данные разом
    func loadAll(userId: String) {
        isLoading = true
        let group = DispatchGroup()

        group.enter()
        loadMyActiveRequests(userId: userId) { group.leave() }

        group.enter()
        loadMyBookedGames(userId: userId) { group.leave() }

        // Завершённые НЕ загружаем — только по запросу
        group.notify(queue: .main) { [weak self] in
            self?.isLoading = false
        }
    }
    
    // MARK: - Отмена бронирования
    // Партнёр отказался — заявка возвращается в ленту (status "active", bookedBy удаляется).
    // Автор отменил — игра закрывается (status "cancelled"): иначе тот же человек мог бы
    // снова забронировать заявку, которую автор уже не хочет проводить.
    // Второй участник получает уведомление с именем того, кто отменил.
    func cancelBooking(requestId: String, completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }

        // Сначала читаем заявку: нужно понять, кто есть кто, и взять дату для текста
        db.collection("sparring_requests").document(requestId).getDocument { [weak self] doc, _ in
            guard let self, let data = doc?.data() else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            let authorId   = data["userId"]   as? String ?? ""
            let bookedById = data["bookedBy"] as? String ?? ""
            let byAuthor   = currentUserId == authorId

            // Уведомляем того, кто НЕ отменяет
            let notifyUserId = byAuthor ? bookedById : authorId

            let dayText = (data["date"] as? Timestamp).map { AppDate.dayLong($0.dateValue()) } ?? ""
            let when = NotificationTexts.when(dateText: dayText, slot: data["timeSlot"] as? String ?? "")

            // Имя того, кто отменяет, берём из его профиля
            UserService.shared.fetchUser(id: currentUserId) { userData in
                let name = UserService.fullName(from: userData ?? [:])

                // Отменяем запланированные локальные уведомления на этом устройстве
                NotificationService.shared.cancelGameNotifications(sparringRequestId: requestId)

                let updateData: [String: Any]
                if byAuthor {
                    updateData = [
                        "status":      "cancelled",
                        "cancelledBy": currentUserId,
                        "cancelledAt": Timestamp()
                    ]
                } else {
                    updateData = [
                        "status":   "active",
                        "bookedBy": FieldValue.delete(),
                        "bookedAt": FieldValue.delete()
                    ]
                }

                self.db.collection("sparring_requests").document(requestId).updateData(updateData) { error in
                    DispatchQueue.main.async {
                        guard error == nil else {
                            completion(false)
                            return
                        }

                        // Диалог уточнения по этой встрече закрываем (если он был)
                        self.db.collection("meeting_clarifications").document(requestId)
                            .updateData(["status": "cancelled"])

                        if !notifyUserId.isEmpty {
                            let copy = NotificationTexts.cancellation(name: name, byAuthor: byAuthor, when: when)
                            NotificationService.shared.saveAndPush(
                                userId: notifyUserId,
                                type: .cancellation,
                                title: copy.title,
                                body: copy.body,
                                targetType: "profile",
                                targetId: currentUserId,
                                actorId: currentUserId,
                                actorName: name
                            )
                        }
                        completion(true)
                    }
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

    // MARK: - Одна заявка (создание, чтение, правка, удаление)

    func createRequest(data: [String: Any], completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }
        db.collection("sparring_requests").addDocument(data: data) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    func fetchRequest(id: String, completion: @escaping ([String: Any]?) -> Void) {
        db.collection("sparring_requests").document(id).getDocument { doc, _ in
            DispatchQueue.main.async { completion(doc?.data()) }
        }
    }

    func updateRequest(id: String, fields: [String: Any], completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }
        db.collection("sparring_requests").document(id).updateData(fields) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    func deleteRequest(id: String, completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }
        db.collection("sparring_requests").document(id).delete { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    // MARK: - Число сыгранных игр игрока (агрегация, без загрузки документов)
    func countCompletedGames(userId: String, completion: @escaping (Int) -> Void) {
        let group = DispatchGroup()
        var asAuthor = 0
        var asPartner = 0

        group.enter()
        db.collection("sparring_requests")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", isEqualTo: "completed")
            .count
            .getAggregation(source: .server) { snapshot, _ in
                asAuthor = Int(truncating: snapshot?.count ?? 0)
                group.leave()
            }

        group.enter()
        db.collection("sparring_requests")
            .whereField("bookedBy", isEqualTo: userId)
            .whereField("status", isEqualTo: "completed")
            .count
            .getAggregation(source: .server) { snapshot, _ in
                asPartner = Int(truncating: snapshot?.count ?? 0)
                group.leave()
            }

        group.notify(queue: .main) { completion(asAuthor + asPartner) }
    }
}
