import Foundation
import Combine
import FirebaseFirestore

class ReviewService: ObservableObject {

    private let db = Firestore.firestore()

    // MARK: - Создать отзыв с автомодерацией
    func submitReview(
        fromUserId: String,
        fromUserName: String,
        toUserId: String,
        sparringRequestId: String,
        rating: Int,
        comment: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        // Прогоняем комментарий через модерацию
        let (cleanedComment, verdict) = ContentModeration.process(comment)

        let moderationStatus: String
        let userMessage: String?

        switch verdict {
        case .approved:
            moderationStatus = "approved"
            userMessage = nil
        case .needsReview(let reason):
            moderationStatus = "pending"
            userMessage = "Отзыв отправлен на модерацию. Причина: \(reason)"
        }

        // Составной ID — защита от дублей
        let docId = "\(sparringRequestId)_\(fromUserId)"

        let data: [String: Any] = [
            "fromUserId":        fromUserId,
            "fromUserName":      fromUserName,
            "toUserId":          toUserId,
            "sparringRequestId": sparringRequestId,
            "rating":            rating,
            "comment":           cleanedComment,
            "moderationStatus":  moderationStatus,
            "reportedCount":     0,
            "createdAt":         Timestamp()
        ]

        db.collection("reviews").document(docId).setData(data, merge: false) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                } else {
                    completion(true, userMessage)
                }
            }
        }
    }

    // MARK: - Проверка: оставлял ли отзыв
    func hasReviewed(
        fromUserId: String,
        sparringRequestId: String,
        completion: @escaping (Bool) -> Void
    ) {
        let docId = "\(sparringRequestId)_\(fromUserId)"
        db.collection("reviews").document(docId).getDocument { snapshot, _ in
            DispatchQueue.main.async {
                completion(snapshot?.exists ?? false)
            }
        }
    }

    // MARK: - Загрузка отзывов (только одобренные)
    func loadReviews(forUserId userId: String, completion: @escaping ([Review]) -> Void) {
        db.collection("reviews")
            .whereField("toUserId", isEqualTo: userId)
            .whereField("moderationStatus", isEqualTo: "approved")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, _ in
                let reviews = snapshot?.documents.compactMap {
                    Review(id: $0.documentID, data: $0.data())
                } ?? []
                DispatchQueue.main.async { completion(reviews) }
            }
    }

    // MARK: - Средний рейтинг
    func loadRatingStats(forUserId userId: String, completion: @escaping (Double, Int) -> Void) {
        db.collection("reviews")
            .whereField("toUserId", isEqualTo: userId)
            .whereField("moderationStatus", isEqualTo: "approved")
            .getDocuments { snapshot, _ in
                let reviews = snapshot?.documents.compactMap {
                    Review(id: $0.documentID, data: $0.data())
                } ?? []

                DispatchQueue.main.async {
                    guard !reviews.isEmpty else {
                        completion(0.0, 0)
                        return
                    }
                    let sum = reviews.reduce(0) { $0 + $1.rating }
                    let avg = Double(sum) / Double(reviews.count)
                    completion(avg, reviews.count)
                }
            }
    }

    // MARK: - Жалоба на отзыв
    func reportReview(reviewId: String, completion: @escaping (Bool) -> Void) {
        db.collection("reviews").document(reviewId).updateData([
            "reportedCount": FieldValue.increment(Int64(1))
        ]) { error in
            // Проверяем — если 3+ жалобы, скрываем
            self.db.collection("reviews").document(reviewId).getDocument { doc, _ in
                if let count = doc?.data()?["reportedCount"] as? Int, count >= 3 {
                    self.db.collection("reviews").document(reviewId).updateData([
                        "moderationStatus": "pending"
                    ])
                }
                DispatchQueue.main.async {
                    completion(error == nil)
                }
            }
        }
    }
    // MARK: - Админские функции

    // Загрузить отзывы на модерации
    func loadPendingReviews(completion: @escaping ([Review]) -> Void) {
        db.collection("reviews")
            .whereField("moderationStatus", isEqualTo: "pending")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, _ in
                let reviews = snapshot?.documents.compactMap {
                    Review(id: $0.documentID, data: $0.data())
                } ?? []
                DispatchQueue.main.async { completion(reviews) }
            }
    }

    // Одобрить
    func approveReview(reviewId: String, completion: @escaping (Bool) -> Void) {
        db.collection("reviews").document(reviewId).updateData([
            "moderationStatus": "approved",
            "reportedCount": 0
        ]) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    // Удалить (soft delete)
    func deleteReview(reviewId: String, completion: @escaping (Bool) -> Void) {
        db.collection("reviews").document(reviewId).updateData([
            "moderationStatus": "deleted"
        ]) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    // Запросить правку у автора — отзыв возвращается со статусом needs_revision
    // и автору приходит локальное уведомление
    func requestRevision(
        reviewId: String,
        fromUserName: String,
        reason: String,
        completion: @escaping (Bool) -> Void
    ) {
        db.collection("reviews").document(reviewId).updateData([
            "moderationStatus": "needs_revision",
            "revisionReason": reason,
            "revisionRequestedAt": Timestamp()
        ]) { error in
            if error == nil {
                // Локальное уведомление автору
                NotificationService.shared.sendRevisionRequestNotice(
                    reviewerName: fromUserName,
                    reason: reason
                )
            }
            DispatchQueue.main.async { completion(error == nil) }
        }
    }
}
