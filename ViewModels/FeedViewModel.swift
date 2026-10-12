import Foundation
import Combine
import FirebaseFirestore

final class FeedViewModel: ObservableObject {

    @Published var displayedRequests: [SparringRequest] = []
    @Published var isLoading = false
    @Published var hasMore = false
    @Published var bookingError: String? = nil

    @Published var filterCity  = "Все города"  { didSet { if oldValue != filterCity  { startListening() } } }
    @Published var filterGrip  = "Любой хват"  { didSet { applyClientFilters() } }
    @Published var filterStyle = "Любой стиль" { didSet { applyClientFilters() } }
    @Published var filterLevel = "Все уровни"  { didSet { applyClientFilters() } }

    var hasActiveFilters: Bool {
        filterCity  != "Все города"  ||
        filterLevel != "Все уровни"  ||
        filterGrip  != "Любой хват"  ||
        filterStyle != "Любой стиль"
    }

    private static let pageSize = 20

    private let db = Firestore.firestore()
    private let currentUserId: String
    private let currentUserName: String
    private var listener: ListenerRegistration?
    private var serverRequests: [SparringRequest] = []
    private var pageLimit = FeedViewModel.pageSize

    init(currentUserId: String, currentUserName: String = "") {
        self.currentUserId   = currentUserId
        self.currentUserName = currentUserName
    }

    deinit { listener?.remove() }

    /// Подписка на ленту. По умолчанию начинает с первой страницы.
    func startListening(resetPaging: Bool = true) {
        listener?.remove()
        isLoading = true
        if resetPaging { pageLimit = Self.pageSize }

        var query: Query = db.collection("sparring_requests")
            .whereField("status", isEqualTo: "active")

        if filterCity != "Все города" {
            query = query.whereField("city", isEqualTo: filterCity)
        }

        let limit = pageLimit
        query = query
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        listener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    debugLog("FeedViewModel error: \(error.localizedDescription)")
                    return
                }

                let documents = snapshot?.documents ?? []
                // Если сервер вернул полную страницу — вероятно, есть ещё
                self.hasMore = documents.count >= limit

                // Блокировки применяются в applyClientFilters, чтобы лента
                // обновлялась и когда список блокировок загрузился позже
                self.serverRequests = documents.compactMap { doc in
                    guard let req = SparringRequest(id: doc.documentID, data: doc.data()),
                          req.userId != self.currentUserId
                    else { return nil }
                    return req
                }
                self.applyClientFilters()
            }
        }
    }

    /// Подгрузить следующую порцию заявок
    func loadMore() {
        guard hasMore, !isLoading else { return }
        pageLimit += Self.pageSize
        startListening(resetPaging: false)
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    private func applyClientFilters() {
        let blockedIds = BlockService.shared.allBlockedIds
        displayedRequests = serverRequests.filter { req in
            let notBlocked = !blockedIds.contains(req.userId)
            let gripOK  = filterGrip  == "Любой хват"  || req.authorGrip      == filterGrip
            let styleOK = filterStyle == "Любой стиль" || req.authorPlayStyle == filterStyle
            // Фильтр по уровню самого автора заявки
            let levelOK = filterLevel == "Все уровни"  || req.authorSkillLevel == filterLevel
            return notBlocked && gripOK && styleOK && levelOK
        }
    }

    func resetFilters() {
        filterGrip  = "Любой хват"
        filterStyle = "Любой стиль"
        filterLevel = "Все уровни"
        filterCity  = "Все города"
    }

    // MARK: - Бронирование

    private static let alreadyBookedCode = 409

    /// Бронирование в транзакции: если заявку успели забронировать или удалить
    /// с момента загрузки ленты, запись не перезапишется.
    func book(request: SparringRequest) {
        guard request.userId != currentUserId else { return }

        // Защита: нельзя забронировать заявку заблокированного (в обе стороны)
        if BlockService.shared.isBlocked(request.userId) {
            bookingError = "Этот игрок недоступен"
            return
        }

        let ref = db.collection("sparring_requests").document(request.id)
        let userId = currentUserId

        db.runTransaction({ transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            guard snapshot.data()?["status"] as? String == "active" else {
                errorPointer?.pointee = NSError(
                    domain: "Spinnet",
                    code: FeedViewModel.alreadyBookedCode,
                    userInfo: [NSLocalizedDescriptionKey: "Заявка уже недоступна"]
                )
                return nil
            }

            transaction.updateData([
                "status":   "booked",
                "bookedBy": userId,
                "bookedAt": Timestamp()
            ], forDocument: ref)
            return nil
        }) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error = error as NSError? {
                    if error.domain == "Spinnet", error.code == FeedViewModel.alreadyBookedCode {
                        self.bookingError = "Эту заявку уже забронировали или удалили. Лента обновлена"
                    } else {
                        self.bookingError = "Не удалось забронировать: \(error.localizedDescription)"
                    }
                    return
                }

                // Уведомление автору заявки — его игру забронировали
                NotificationService.shared.saveAndPush(
                    userId: request.userId,
                    type: .requestBooked,
                    title: "Вашу заявку забронировали 🏓",
                    body: "\(self.currentUserName.isEmpty ? "Игрок" : self.currentUserName) хочет сыграть с вами \(self.formatDate(request.date)) в \(request.timeSlot)",
                    targetType: "game",
                    targetId: request.id
                )

                // Планируем локальные напоминания (на устройстве забронировавшего)
                NotificationService.shared.scheduleGameReminder(
                    sparringRequestId: request.id,
                    partnerName: request.authorFullName,
                    gameDate: request.date,
                    timeSlot: request.timeSlot
                )
                NotificationService.shared.scheduleReviewReminder(
                    sparringRequestId: request.id,
                    partnerName: request.authorFullName,
                    gameDate: request.date,
                    timeSlot: request.timeSlot
                )
            }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f
    }()

    private func formatDate(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }
}
