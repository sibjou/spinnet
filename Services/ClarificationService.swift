import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

// Кто совершает действие в диалоге
struct ChatActor {
    let id: String
    let name: String
}

class ClarificationService: ObservableObject {

    @Published var clarifications: [MeetingClarification] = []
    @Published var unreadClarificationsCount: Int = 0
    @Published var isLoading = false
    @Published var hasLoaded = false      // список получил первый ответ

    private let db = Firestore.firestore()

    // Список диалогов: два запроса (я автор / я забронировал), результаты склеиваются
    private var listListeners: [ListenerRegistration] = []
    private var listeningUserId: String?
    private var authorItems: [MeetingClarification] = []
    private var bookedItems: [MeetingClarification] = []

    // Один открытый диалог
    private var actionsListener: ListenerRegistration?
    private var metaListener: ListenerRegistration?

    // Счётчик непрочитанных для вкладки «Встречи»
    private var unreadListeners: [ListenerRegistration] = []
    private var unreadAsAuthor = 0
    private var unreadAsBooked = 0

    deinit {
        listListeners.forEach { $0.remove() }
        actionsListener?.remove()
        metaListener?.remove()
        unreadListeners.forEach { $0.remove() }
    }

    // MARK: - Создать уточнение при бронировании
    func createClarification(
        sparringRequest: SparringRequest,
        bookedById: String,
        bookedByName: String,
        completion: @escaping (String?) -> Void
    ) {
        guard ConnectionMonitor.shared.allowWrite(otherwiseNil: completion) else { return }
        let data: [String: Any] = [
            "sparringRequestId": sparringRequest.id,
            "authorId":          sparringRequest.userId,
            "authorName":        sparringRequest.authorFullName,
            "bookedById":        bookedById,
            "bookedByName":      bookedByName,
            "sparringDate":      Timestamp(date: sparringRequest.date),
            "sparringTimeSlot":  sparringRequest.timeSlot,
            "sparringCity":      sparringRequest.city,
            "sparringLocation":  sparringRequest.location,
            "status":            "active",
            "createdAt":         Timestamp(),
            "updatedAt":         Timestamp()
        ]

        let docId = sparringRequest.id
        db.collection("meeting_clarifications").document(docId).setData(data, merge: false) { error in
            DispatchQueue.main.async {
                completion(error == nil ? docId : nil)
            }
        }
    }

    // MARK: - Список диалогов в реальном времени

    func startListening(userId: String) {
        // Подписка уже идёт для этого человека — повторный вызов (возврат из диалога) её не перезапускает
        if listeningUserId == userId, !listListeners.isEmpty { return }

        // Сначала снимаем старые подписки, чтобы они не дублировались при повторном вызове
        listListeners.forEach { $0.remove() }
        listListeners = []
        listeningUserId = userId

        // Загрузчик показываем только пока данных ещё не было
        if !hasLoaded { isLoading = true }

        // Сортировку делаем сами (по последней активности), поэтому составной индекс не нужен
        let asAuthor = db.collection("meeting_clarifications")
            .whereField("authorId", isEqualTo: userId)
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { [weak self] snapshot, _ in
                let items = snapshot?.documents.compactMap {
                    MeetingClarification(id: $0.documentID, data: $0.data())
                } ?? []
                DispatchQueue.main.async {
                    self?.authorItems = items
                    self?.publish()
                }
            }

        let asBooked = db.collection("meeting_clarifications")
            .whereField("bookedById", isEqualTo: userId)
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { [weak self] snapshot, _ in
                let items = snapshot?.documents.compactMap {
                    MeetingClarification(id: $0.documentID, data: $0.data())
                } ?? []
                DispatchQueue.main.async {
                    self?.bookedItems = items
                    self?.publish()
                }
            }

        listListeners = [asAuthor, asBooked]
    }

    func stopListening() {
        listListeners.forEach { $0.remove() }
        listListeners = []
        listeningUserId = nil
    }

    /// Склеивает оба запроса, убирает повторы, сортирует по последней активности
    private func publish() {
        var seen = Set<String>()
        let all = (authorItems + bookedItems)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.activityDate > $1.activityDate }

        clarifications = all
        isLoading = false
        hasLoaded = true
    }

    /// Обновление по жесту «потянуть вниз»: перечитывает диалоги и ждёт ответа, но не дольше `RefreshWait.timeout`
    func refresh(userId: String) async {
        await RefreshWait.wait { finish in
            let group = DispatchGroup()
            var fetchedAuthor: [MeetingClarification]?
            var fetchedBooked: [MeetingClarification]?

            group.enter()
            db.collection("meeting_clarifications")
                .whereField("authorId", isEqualTo: userId)
                .whereField("status", isEqualTo: "active")
                .getDocuments { snapshot, _ in
                    fetchedAuthor = snapshot?.documents.compactMap {
                        MeetingClarification(id: $0.documentID, data: $0.data())
                    }
                    group.leave()
                }

            group.enter()
            db.collection("meeting_clarifications")
                .whereField("bookedById", isEqualTo: userId)
                .whereField("status", isEqualTo: "active")
                .getDocuments { snapshot, _ in
                    fetchedBooked = snapshot?.documents.compactMap {
                        MeetingClarification(id: $0.documentID, data: $0.data())
                    }
                    group.leave()
                }

            group.notify(queue: .main) { [weak self] in
                // Если запрос не удался (нет сети), оставляем то, что уже есть
                if let fetchedAuthor { self?.authorItems = fetchedAuthor }
                if let fetchedBooked { self?.bookedItems = fetchedBooked }
                self?.publish()
                finish()
            }
        }
        // Чтобы обновление не мигало, если ответ пришёл мгновенно
        try? await Task.sleep(nanoseconds: 350_000_000)
    }

    // MARK: - Один диалог

    func fetchClarification(id: String, completion: @escaping (MeetingClarification?) -> Void) {
        db.collection("meeting_clarifications").document(id).getDocument { snapshot, _ in
            let clarification = snapshot?.data().flatMap { MeetingClarification(id: id, data: $0) }
            DispatchQueue.main.async {
                completion(clarification?.status == "active" ? clarification : nil)
            }
        }
    }

    /// Слушает сам диалог: прочитанность партнёром, смена времени и места
    func listenClarification(id: String, onChange: @escaping (MeetingClarification?) -> Void) {
        metaListener?.remove()
        metaListener = db.collection("meeting_clarifications").document(id)
            .addSnapshotListener { snapshot, _ in
                let clarification = snapshot?.data().flatMap { MeetingClarification(id: id, data: $0) }
                DispatchQueue.main.async { onChange(clarification) }
            }
    }

    func stopMetaListener() {
        metaListener?.remove()
        metaListener = nil
    }

    /// Человек открыл диалог: непрочитанных у него больше нет
    func markRead(clarificationId: String, userId: String) {
        db.collection("meeting_clarifications").document(clarificationId).updateData([
            "unread.\(userId)": 0,
            "readAt.\(userId)": Timestamp()
        ])
    }

    // MARK: - Действия в реальном времени

    func loadActions(clarificationId: String, completion: @escaping ([MeetingAction]) -> Void) {
        actionsListener?.remove()

        // Сортируем сами по времени: так не нужен составной индекс Firestore
        actionsListener = db.collection("meeting_actions")
            .whereField("clarificationId", isEqualTo: clarificationId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    debugLog("Actions listener error: \(error.localizedDescription)")
                    return
                }
                let actions = (snapshot?.documents.compactMap {
                    MeetingAction(id: $0.documentID, data: $0.data())
                } ?? []).sorted { $0.createdAt < $1.createdAt }
                DispatchQueue.main.async { completion(actions) }
            }
    }

    func stopActionsListener() {
        actionsListener?.remove()
        actionsListener = nil
    }

    // MARK: - Отправить действие
    // Одним пакетом: само действие и обновление диалога (последнее событие, счётчик
    // непрочитанных у партнёра). Если диалог ещё «черновик» — он создаётся вместе с первым
    // действием, чтобы у партнёра не появлялись пустые диалоги.
    // Партнёр получает уведомление.
    func send(
        _ action: OutgoingAction,
        in clarification: MeetingClarification,
        isDraft: Bool,
        from sender: ChatActor,
        completion: @escaping (String?) -> Void
    ) {
        guard ConnectionMonitor.shared.allowWrite(otherwiseNil: completion) else { return }
        // Диалог хранится под id заявки
        let clarificationId = clarification.sparringRequestId

        guard isDraft else {
            commitSend(action, clarification: clarification, clarificationId: clarificationId,
                       isDraft: false, sender: sender, completion: completion)
            return
        }

        // Если диалог раньше удаляли, от него могли остаться старые действия — чистим
        db.collection("meeting_actions")
            .whereField("clarificationId", isEqualTo: clarificationId)
            .getDocuments { [weak self] snapshot, _ in
                guard let self else { return }
                let old = snapshot?.documents ?? []
                guard !old.isEmpty else {
                    self.commitSend(action, clarification: clarification, clarificationId: clarificationId,
                                    isDraft: true, sender: sender, completion: completion)
                    return
                }
                let cleanBatch = self.db.batch()
                old.forEach { cleanBatch.deleteDocument($0.reference) }
                cleanBatch.commit { _ in
                    debugLog("Очищено \(old.count) старых действий перед созданием диалога")
                    self.commitSend(action, clarification: clarification, clarificationId: clarificationId,
                                    isDraft: true, sender: sender, completion: completion)
                }
            }
    }

    private func commitSend(
        _ action: OutgoingAction,
        clarification: MeetingClarification,
        clarificationId: String,
        isDraft: Bool,
        sender: ChatActor,
        completion: @escaping (String?) -> Void
    ) {
        let now = Timestamp()
        let partnerId = clarification.partnerId(currentUserId: sender.id)
        let preview = action.previewText()

        var actionData: [String: Any] = [
            "clarificationId": clarificationId,
            "fromUserId":      sender.id,
            "fromUserName":    sender.name,
            "type":            action.type.rawValue,
            "proposedValue":   action.value,
            "status":          action.status.rawValue,
            "createdAt":       now
        ]
        if let latitude = action.latitude, let longitude = action.longitude {
            actionData["latitude"] = latitude
            actionData["longitude"] = longitude
        }
        if !action.note.isEmpty { actionData["note"] = action.note }
        if let day = action.proposedDate { actionData["proposedDate"] = Timestamp(date: day) }

        let batch = db.batch()
        let clarificationRef = db.collection("meeting_clarifications").document(clarificationId)
        let actionRef = db.collection("meeting_actions").document()
        batch.setData(actionData, forDocument: actionRef)

        if isDraft {
            var document: [String: Any] = [
                "sparringRequestId": clarification.sparringRequestId,
                "authorId":          clarification.authorId,
                "authorName":        clarification.authorName,
                "bookedById":        clarification.bookedById,
                "bookedByName":      clarification.bookedByName,
                "sparringDate":      Timestamp(date: clarification.sparringDate),
                "sparringTimeSlot":  clarification.sparringTimeSlot,
                "sparringCity":      clarification.sparringCity,
                "sparringLocation":  clarification.sparringLocation,
                "status":            "active",
                "createdAt":         now,
                "updatedAt":         now,
                "lastActionAt":      now,
                "lastActionBy":      sender.id,
                "lastActionText":    preview,
                // В setData вложенные поля задаются словарями, а не «a.b»
                "unread":            [partnerId: 1],
                "readAt":            [sender.id: now]
            ]
            if let latitude = clarification.sparringLatitude, let longitude = clarification.sparringLongitude {
                document["sparringLatitude"] = latitude
                document["sparringLongitude"] = longitude
            }
            batch.setData(document, forDocument: clarificationRef)
        } else {
            batch.updateData([
                "updatedAt":              now,
                "lastActionAt":           now,
                "lastActionBy":           sender.id,
                "lastActionText":         preview,
                "unread.\(partnerId)":    FieldValue.increment(Int64(1)),
                "readAt.\(sender.id)":    now
            ], forDocument: clarificationRef)
        }

        batch.commit { error in
            DispatchQueue.main.async {
                if let error {
                    debugLog("Уточнение: не удалось отправить (\(error.localizedDescription))")
                    completion(nil)
                    return
                }

                // Сообщение видно партнёру во вкладке «Чаты» (непрочитанное на значке и в списке).
                // В «Уведомления» оно не дублируется: колокольчик — для событий вне переписки.
                completion(clarificationId)
            }
        }
    }

    // MARK: - Ответить на предложение
    // Принятое время и место сразу меняют саму заявку и диалог.
    // Ответ — тоже событие: автор предложения видит его непрочитанным и получает уведомление.
    func respondToAction(
        action: MeetingAction,
        clarification: MeetingClarification,
        clarificationId: String,
        responder: ChatActor,
        accept: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }
        let now = Timestamp()
        let batch = db.batch()

        let actionRef = db.collection("meeting_actions").document(action.id)
        let requestRef = db.collection("sparring_requests").document(clarification.sparringRequestId)
        let clarificationRef = db.collection("meeting_clarifications").document(clarificationId)

        batch.updateData([
            "status": accept ? MeetingActionStatus.accepted.rawValue : MeetingActionStatus.declined.rawValue
        ], forDocument: actionRef)

        var clarificationUpdates: [String: Any] = [:]

        if accept {
            switch action.type {
            case .suggestTime:
                var requestFields: [String: Any] = ["timeSlot": action.proposedValue]
                clarificationUpdates["sparringTimeSlot"] = action.proposedValue
                if let day = action.proposedDate {
                    let start = Calendar.current.startOfDay(for: day)
                    requestFields["date"] = Timestamp(date: start)
                    clarificationUpdates["sparringDate"] = Timestamp(date: start)
                }
                batch.updateData(requestFields, forDocument: requestRef)

            case .suggestLocation:
                var requestFields: [String: Any] = ["location": action.proposedValue]
                clarificationUpdates["sparringLocation"] = action.proposedValue
                if let latitude = action.latitude, let longitude = action.longitude {
                    requestFields["locationLatitude"] = latitude
                    requestFields["locationLongitude"] = longitude
                    clarificationUpdates["sparringLatitude"] = latitude
                    clarificationUpdates["sparringLongitude"] = longitude
                }
                batch.updateData(requestFields, forDocument: requestRef)

            case .cancelRequest:
                // Отмену предложил автор — игра закрывается; предложил забронировавший — заявка возвращается в ленту
                if action.fromUserId == clarification.authorId {
                    batch.updateData([
                        "status":      "cancelled",
                        "cancelledBy": action.fromUserId,
                        "cancelledAt": now
                    ], forDocument: requestRef)
                } else {
                    batch.updateData([
                        "status":   "active",
                        "bookedBy": FieldValue.delete(),
                        "bookedAt": FieldValue.delete()
                    ], forDocument: requestRef)
                }
                clarificationUpdates["status"] = "cancelled"

            case .confirm, .message, .late, .arrived:
                break
            }
        }

        let original = OutgoingAction(
            type: action.type, value: action.proposedValue,
            latitude: action.latitude, longitude: action.longitude,
            note: action.note, proposedDate: action.proposedDate
        )
        let summary = original.previewText()
        let verdict = accept ? "Принято" : "Отклонено"

        clarificationUpdates["updatedAt"] = now
        clarificationUpdates["lastActionAt"] = now
        clarificationUpdates["lastActionBy"] = responder.id
        clarificationUpdates["lastActionText"] = "\(verdict): \(summary)"
        clarificationUpdates["unread.\(action.fromUserId)"] = FieldValue.increment(Int64(1))
        clarificationUpdates["readAt.\(responder.id)"] = now
        batch.updateData(clarificationUpdates, forDocument: clarificationRef)

        batch.commit { error in
            DispatchQueue.main.async {
                guard error == nil else {
                    completion(false)
                    return
                }

                if accept && action.type == .cancelRequest {
                    NotificationService.shared.cancelGameNotifications(sparringRequestId: clarification.sparringRequestId)
                }

                // Ответ виден в чате (непрочитанное у автора предложения), в «Уведомления» не дублируется
                completion(true)
            }
        }
    }

    // MARK: - Удалить уточнение и все его действия
    func deleteClarification(id: String) {
        // Помечаем сам диалог как удалённый
        db.collection("meeting_clarifications").document(id).updateData([
            "status": "deleted"
        ])

        // Удаляем все связанные действия физически — чтобы при пересоздании
        // диалога старые сообщения не подгружались
        db.collection("meeting_actions")
            .whereField("clarificationId", isEqualTo: id)
            .getDocuments { [weak self] snapshot, _ in
                guard let documents = snapshot?.documents,
                      let self = self else { return }

                let batch = self.db.batch()
                for doc in documents {
                    batch.deleteDocument(doc.reference)
                }
                batch.commit { _ in
                    debugLog("Удалено \(documents.count) действий диалога \(id)")
                }
            }
    }

    // MARK: - Непрочитанное для вкладки «Встречи»
    // Сумма непрочитанных событий по всем моим диалогам. Слушаем только свои диалоги,
    // а не чужие действия, как раньше.
    func startUnreadListener(currentUserId: String) {
        stopUnreadListener()

        let asAuthor = db.collection("meeting_clarifications")
            .whereField("authorId", isEqualTo: currentUserId)
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { [weak self] snapshot, _ in
                let total = ClarificationService.unreadTotal(snapshot?.documents ?? [], for: currentUserId)
                DispatchQueue.main.async {
                    self?.unreadAsAuthor = total
                    self?.publishUnread()
                }
            }

        let asBooked = db.collection("meeting_clarifications")
            .whereField("bookedById", isEqualTo: currentUserId)
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { [weak self] snapshot, _ in
                let total = ClarificationService.unreadTotal(snapshot?.documents ?? [], for: currentUserId)
                DispatchQueue.main.async {
                    self?.unreadAsBooked = total
                    self?.publishUnread()
                }
            }

        unreadListeners = [asAuthor, asBooked]
    }

    func stopUnreadListener() {
        unreadListeners.forEach { $0.remove() }
        unreadListeners = []
    }

    private func publishUnread() {
        unreadClarificationsCount = unreadAsAuthor + unreadAsBooked
    }

    private static func unreadTotal(_ documents: [QueryDocumentSnapshot], for userId: String) -> Int {
        documents.reduce(0) { sum, doc in
            let map = doc.data()["unread"] as? [String: Any]
            return sum + max((map?[userId] as? Int) ?? 0, 0)
        }
    }

    // MARK: - Активный диалог по заявке (если уже есть)
    // Диалог хранится под id заявки, поэтому его читаем напрямую, без поиска по базе.
    func findActiveClarification(forRequestId requestId: String,
                                 completion: @escaping (MeetingClarification?) -> Void) {
        fetchClarification(id: requestId, completion: completion)
    }
}
