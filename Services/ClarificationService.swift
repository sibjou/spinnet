import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

class ClarificationService: ObservableObject {
    
    @Published var clarifications: [MeetingClarification] = []
    @Published var unreadClarificationsCount: Int = 0
    @Published var isLoading = false
    
    private var activeListeners: [ListenerRegistration] = []
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var actionsListener: ListenerRegistration?
    
    deinit {
        activeListeners.forEach { $0.remove() }
        listener?.remove()
        actionsListener?.remove()
        unreadListener?.remove()
    }
    
    // MARK: - Создать диалог И первое действие одновременно
    // Используется когда пользователь отправляет первое предложение в "draft"-диалоге.
    // До этого момента запись в Firestore не создаётся,
    // чтобы не засорять список уточнений у партнёра пустыми диалогами.
    func createDraftWithFirstAction(
        draftClarification: MeetingClarification,
        actionType: MeetingActionType,
        proposedValue: String,
        fromUserId: String,
        fromUserName: String,
        completion: @escaping (String?) -> Void
    ) {

        let realId = draftClarification.sparringRequestId

        // Сначала удаляем старые actions если они остались от удалённого диалога
        db.collection("meeting_actions")
            .whereField("clarificationId", isEqualTo: realId)
            .getDocuments { [weak self] snapshot, _ in
                guard let self = self else { return }

                // Удаляем старые actions
                if let documents = snapshot?.documents, !documents.isEmpty {
                    let cleanBatch = self.db.batch()
                    for doc in documents {
                        cleanBatch.deleteDocument(doc.reference)
                    }
                    cleanBatch.commit { _ in
                        debugLog("🗑 Очищено \(documents.count) старых actions перед созданием draft")
                        // Теперь создаём новый диалог + первое действие
                        self.performDraftCreation(
                            draftClarification: draftClarification,
                            actionType: actionType,
                            proposedValue: proposedValue,
                            fromUserId: fromUserId,
                            fromUserName: fromUserName,
                            realId: realId,
                            completion: completion
                        )
                    }
                } else {
                    // Старых нет — сразу создаём
                    self.performDraftCreation(
                        draftClarification: draftClarification,
                        actionType: actionType,
                        proposedValue: proposedValue,
                        fromUserId: fromUserId,
                        fromUserName: fromUserName,
                        realId: realId,
                        completion: completion
                    )
                }
            }
    }

    // Вспомогательная функция — собственно создание (batch)
    private func performDraftCreation(
        draftClarification: MeetingClarification,
        actionType: MeetingActionType,
        proposedValue: String,
        fromUserId: String,
        fromUserName: String,
        realId: String,
        completion: @escaping (String?) -> Void
    ) {
        let clarificationData: [String: Any] = [
            "sparringRequestId": draftClarification.sparringRequestId,
            "authorId":          draftClarification.authorId,
            "authorName":        draftClarification.authorName,
            "bookedById":        draftClarification.bookedById,
            "bookedByName":      draftClarification.bookedByName,
            "sparringDate":      Timestamp(date: draftClarification.sparringDate),
            "sparringTimeSlot":  draftClarification.sparringTimeSlot,
            "sparringCity":      draftClarification.sparringCity,
            "sparringLocation":  draftClarification.sparringLocation,
            "status":            "active",
            "createdAt":         Timestamp(),
            "updatedAt":         Timestamp()
        ]

        let actionData: [String: Any] = [
            "clarificationId": realId,
            "fromUserId":      fromUserId,
            "fromUserName":    fromUserName,
            "type":            actionType.rawValue,
            "proposedValue":   proposedValue,
            "status":          MeetingActionStatus.pending.rawValue,
            "createdAt":       Timestamp()
        ]

        let batch = db.batch()
        let clarRef   = db.collection("meeting_clarifications").document(realId)
        let actionRef = db.collection("meeting_actions").document()

        batch.setData(clarificationData, forDocument: clarRef)
        batch.setData(actionData, forDocument: actionRef)

        batch.commit { error in
            DispatchQueue.main.async {
                if let error = error {
                    debugLog("❌ Ошибка batch.commit: \(error.localizedDescription)")
                } else {
                    debugLog("✅ Batch успешно сохранён, realId: \(realId)")
                }
                completion(error == nil ? realId : nil)
            }
        }
    }
    // MARK: - Создать уточнение при бронировании
    func createClarification(
        sparringRequest: SparringRequest,
        bookedById: String,
        bookedByName: String,
        completion: @escaping (String?) -> Void
    ) {
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
    
    // MARK: - Слушать уточнения текущего пользователя
    func startListening(userId: String) {
        // Сначала чистим старые слушатели чтобы не дублировались при повторном вызове
        activeListeners.forEach { $0.remove() }
        activeListeners = []
        
        var listenerForAuthor: ListenerRegistration?
        var listenerForBookedBy: ListenerRegistration?
        
        var asAuthor: [MeetingClarification] = []
        var asBookedBy: [MeetingClarification] = []
        
        let updateClarifications: () -> Void = { [weak self] in
            var seen = Set<String>()
            let all = (asAuthor + asBookedBy)
                .filter { clar in
                    if seen.contains(clar.id) { return false }
                    seen.insert(clar.id)
                    return true
                }
                .sorted { $0.updatedAt > $1.updatedAt }
            
            DispatchQueue.main.async {
                self?.clarifications = all
                self?.isLoading = false
            }
        }
        
        // Listener для диалогов где я автор
        listenerForAuthor = db.collection("meeting_clarifications")
            .whereField("authorId", isEqualTo: userId)
            .whereField("status", isEqualTo: "active")
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                asAuthor = snapshot?.documents.compactMap {
                    MeetingClarification(id: $0.documentID, data: $0.data())
                } ?? []
                updateClarifications()
            }
        
        // Listener для диалогов где я забронировал
        listenerForBookedBy = db.collection("meeting_clarifications")
            .whereField("bookedById", isEqualTo: userId)
            .whereField("status", isEqualTo: "active")
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                asBookedBy = snapshot?.documents.compactMap {
                    MeetingClarification(id: $0.documentID, data: $0.data())
                } ?? []
                updateClarifications()
            }
        
        // Сохраняем оба listener'а через массив
        self.activeListeners = [listenerForAuthor, listenerForBookedBy].compactMap { $0 }
        
        isLoading = true
    }
    
    func stopListening() {
        activeListeners.forEach { $0.remove() }
        activeListeners = []
        listener?.remove()
        listener = nil
    }
    
    // MARK: - Загрузить действия в реальном времени
    func loadActions(clarificationId: String, completion: @escaping ([MeetingAction]) -> Void) {
        actionsListener?.remove()
        
        actionsListener = db.collection("meeting_actions")
            .whereField("clarificationId", isEqualTo: clarificationId)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    debugLog("Actions listener error: \(error.localizedDescription)")
                    return
                }
                let actions = snapshot?.documents.compactMap {
                    MeetingAction(id: $0.documentID, data: $0.data())
                } ?? []
                DispatchQueue.main.async { completion(actions) }
            }
    }
    
    func stopActionsListener() {
        actionsListener?.remove()
        actionsListener = nil
    }
    
    // MARK: - Отправить действие
    func sendAction(
        clarificationId: String,
        fromUserId: String,
        fromUserName: String,
        type: MeetingActionType,
        proposedValue: String = "",
        completion: @escaping (Bool) -> Void
    ) {
        let data: [String: Any] = [
            "clarificationId": clarificationId,
            "fromUserId":      fromUserId,
            "fromUserName":    fromUserName,
            "type":            type.rawValue,
            "proposedValue":   proposedValue,
            "status":          MeetingActionStatus.pending.rawValue,
            "createdAt":       Timestamp()
        ]
        
        db.collection("meeting_actions").addDocument(data: data) { [weak self] error in
            if error == nil {
                self?.db.collection("meeting_clarifications")
                    .document(clarificationId)
                    .updateData(["updatedAt": Timestamp()])
            }
            DispatchQueue.main.async { completion(error == nil) }
        }
    }
    
    // MARK: - Ответить на предложение
    func respondToAction(
        actionId: String,
        clarificationId: String,
        sparringRequestId: String,
        accept: Bool,
        action: MeetingAction,
        completion: @escaping (Bool) -> Void
    ) {
        let newStatus = accept ? MeetingActionStatus.accepted.rawValue
        : MeetingActionStatus.declined.rawValue
        
        let batch = db.batch()
        
        let actionRef = db.collection("meeting_actions").document(actionId)
        batch.updateData(["status": newStatus], forDocument: actionRef)
        
        if accept {
            let requestRef = db.collection("sparring_requests").document(sparringRequestId)
            switch action.type {
            case .suggestTime:
                batch.updateData(["timeSlot": action.proposedValue], forDocument: requestRef)
                let clarRef = db.collection("meeting_clarifications").document(clarificationId)
                batch.updateData([
                    "sparringTimeSlot": action.proposedValue,
                    "updatedAt": Timestamp()
                ], forDocument: clarRef)
                
            case .suggestLocation:
                batch.updateData(["location": action.proposedValue], forDocument: requestRef)
                let clarRef = db.collection("meeting_clarifications").document(clarificationId)
                batch.updateData([
                    "sparringLocation": action.proposedValue,
                    "updatedAt": Timestamp()
                ], forDocument: clarRef)
                
            case .cancelRequest:
                batch.updateData([
                    "status":   "active",
                    "bookedBy": FieldValue.delete(),
                    "bookedAt": FieldValue.delete()
                ], forDocument: requestRef)
                let clarRef = db.collection("meeting_clarifications").document(clarificationId)
                batch.updateData(["status": "cancelled"], forDocument: clarRef)
                
            case .confirm:
                break
            }
        }
        
        batch.commit { [weak self] error in
            DispatchQueue.main.async {
                if let userId = Auth.auth().currentUser?.uid {
                    self?.refreshUnreadCount(currentUserId: userId)
                }
                completion(error == nil)
            }
        }
    }
    
    // MARK: - Удалить уточнение и все его действия
    func deleteClarification(id: String) {
        // Помечаем сам диалог как удалённый
        db.collection("meeting_clarifications").document(id).updateData([
            "status": "deleted"
        ])

        // Удаляем все связанные actions физически — чтобы при пересоздании
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
                    debugLog("🗑 Удалено \(documents.count) actions для clarification \(id)")
                }
            }
    }
    
    // MARK: - Подсчёт непрочитанных уточнений
    // Считаем только pending-действия в АКТИВНЫХ диалогах где я участник
    func refreshUnreadCount(currentUserId: String) {
        // Сначала получаем ID активных диалогов где я участник
        var myClarificationIds = Set<String>()
        let group = DispatchGroup()
        
        group.enter()
        db.collection("meeting_clarifications")
            .whereField("authorId", isEqualTo: currentUserId)
            .whereField("status", isEqualTo: "active")
            .getDocuments { snapshot, _ in
                snapshot?.documents.forEach { myClarificationIds.insert($0.documentID) }
                group.leave()
            }
        
        group.enter()
        db.collection("meeting_clarifications")
            .whereField("bookedById", isEqualTo: currentUserId)
            .whereField("status", isEqualTo: "active")
            .getDocuments { snapshot, _ in
                snapshot?.documents.forEach { myClarificationIds.insert($0.documentID) }
                group.leave()
            }
        
        group.notify(queue: .main) { [weak self] in
            guard !myClarificationIds.isEmpty else {
                self?.unreadClarificationsCount = 0
                return
            }
            
            // Считаем pending-действия только в моих активных диалогах
            self?.db.collection("meeting_actions")
                .whereField("status", isEqualTo: "pending")
                .getDocuments { snapshot, _ in
                    guard let documents = snapshot?.documents else {
                        DispatchQueue.main.async {
                            self?.unreadClarificationsCount = 0
                        }
                        return
                    }
                    
                    let count = documents.filter { doc in
                        let data = doc.data()
                        let clarId = data["clarificationId"] as? String ?? ""
                        let fromUserId = data["fromUserId"] as? String ?? ""
                        // pending + от другого + в активном диалоге где я участник
                        return myClarificationIds.contains(clarId) && fromUserId != currentUserId
                    }.count
                    
                    DispatchQueue.main.async {
                        self?.unreadClarificationsCount = count
                    }
                }
        }
    }
    private var unreadListener: ListenerRegistration?

    // MARK: - Слушать счётчик непрочитанных в реальном времени
    func startUnreadListener(currentUserId: String) {
        unreadListener?.remove()

        // Слушаем все pending-действия, пересчитываем при любом изменении
        unreadListener = db.collection("meeting_actions")
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self = self else { return }

                let pendingDocs = snapshot?.documents ?? []

                // Получаем мои активные диалоги, чтобы считать только их
                var myClarificationIds = Set<String>()
                let group = DispatchGroup()

                group.enter()
                self.db.collection("meeting_clarifications")
                    .whereField("authorId", isEqualTo: currentUserId)
                    .whereField("status", isEqualTo: "active")
                    .getDocuments { snap, _ in
                        snap?.documents.forEach { myClarificationIds.insert($0.documentID) }
                        group.leave()
                    }

                group.enter()
                self.db.collection("meeting_clarifications")
                    .whereField("bookedById", isEqualTo: currentUserId)
                    .whereField("status", isEqualTo: "active")
                    .getDocuments { snap, _ in
                        snap?.documents.forEach { myClarificationIds.insert($0.documentID) }
                        group.leave()
                    }

                group.notify(queue: .main) {
                    let count = pendingDocs.filter { doc in
                        let data = doc.data()
                        let clarId = data["clarificationId"] as? String ?? ""
                        let fromUserId = data["fromUserId"] as? String ?? ""
                        return myClarificationIds.contains(clarId) && fromUserId != currentUserId
                    }.count

                    self.unreadClarificationsCount = count
                }
            }
    }

    func stopUnreadListener() {
        unreadListener?.remove()
        unreadListener = nil
    }

    // MARK: - Активный диалог по заявке (если уже есть)
    func findActiveClarification(forRequestId requestId: String,
                                 completion: @escaping (MeetingClarification?) -> Void) {
        db.collection("meeting_clarifications")
            .whereField("sparringRequestId", isEqualTo: requestId)
            .whereField("status", isEqualTo: "active")
            .limit(to: 1)
            .getDocuments { snapshot, _ in
                DispatchQueue.main.async {
                    if let doc = snapshot?.documents.first {
                        completion(MeetingClarification(id: doc.documentID, data: doc.data()))
                    } else {
                        completion(nil)
                    }
                }
            }
    }
}
