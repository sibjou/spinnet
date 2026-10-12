import Foundation
import Combine
import FirebaseFirestore

final class FeedViewModel: ObservableObject {

    @Published var displayedRequests: [SparringRequest] = []
    @Published var isLoading = false
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

    private let db = Firestore.firestore()
    private let currentUserId: String
    private let currentUserName: String
    private var listener: ListenerRegistration?
    private var serverRequests: [SparringRequest] = []

    init(currentUserId: String, currentUserName: String = "") {
        self.currentUserId   = currentUserId
        self.currentUserName = currentUserName
    }

    deinit { listener?.remove() }

    func startListening() {
        listener?.remove()
        isLoading = true

        var query: Query = db.collection("sparring_requests")
            .whereField("status", isEqualTo: "active")

        if filterCity != "Все города" {
            query = query.whereField("city", isEqualTo: filterCity)
        }

        query = query
            .order(by: "createdAt", descending: true)
            .limit(to: 20)

        listener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    print("FeedViewModel error: \(error.localizedDescription)")
                    return
                }

                let blockedIds = BlockService.shared.allBlockedIds   // берём список заблокированных

                self.serverRequests = snapshot?.documents.compactMap { doc in
                    guard let req = SparringRequest(id: doc.documentID, data: doc.data()),
                          req.userId != self.currentUserId,
                          !blockedIds.contains(req.userId)            // пропускаем заявки от заблокированных
                    else { return nil }
                    return req
                } ?? []
                self.applyClientFilters()
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    private func applyClientFilters() {
        displayedRequests = serverRequests.filter { req in
            let gripOK  = filterGrip  == "Любой хват"  || req.authorGrip      == filterGrip
            let styleOK = filterStyle == "Любой стиль" || req.authorPlayStyle == filterStyle
            // Фильтр по уровню самого автора заявки
            let levelOK = filterLevel == "Все уровни"  || req.authorSkillLevel == filterLevel
            return gripOK && styleOK && levelOK
        }
    }

    func resetFilters() {
        filterGrip  = "Любой хват"
        filterStyle = "Любой стиль"
        filterLevel = "Все уровни"
        filterCity  = "Все города"
    }

    func book(request: SparringRequest) {
        // Защита: нельзя забронировать заявку заблокированного (в обе стороны)
            if BlockService.shared.isBlocked(request.userId) {
                self.bookingError = "Этот игрок недоступен"
                return
            }

            db.collection("sparring_requests").document(request.id).updateData([
                "status":   "booked",
                "bookedBy": currentUserId,
                "bookedAt": Timestamp()
            ]) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.bookingError = "Ошибка: \(error.localizedDescription)"
                    return
                }

                // Уведомление автору заявки — его игру забронировали
                NotificationService.shared.saveAndPush(
                    userId: request.userId,
                    type: .requestBooked,
                    title: "Вашу заявку забронировали 🏓",
                    body: "\(self?.currentUserName ?? "Игрок") хочет сыграть с вами \(self?.formatDate(request.date) ?? "") в \(request.timeSlot)",
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
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f.string(from: date)
    }
}
