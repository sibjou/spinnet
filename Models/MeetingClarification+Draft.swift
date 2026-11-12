import Foundation

// MARK: - Черновик диалога
// Сразу после брони диалога в базе ещё нет: он появится, когда кто-то из двоих напишет первым.
// Чтобы человек попал в чат в один шаг, экран строит «черновик» с номером draft_<заявка>:
// чат открывается так же, как настоящий, а при первой отправке записывается в базу.

extension MeetingClarification {

    /// Идентификатор черновика по заявке
    static func draftId(requestId: String) -> String { "draft_\(requestId)" }

    /// Диалог по заявке сразу после брони: автор — тот, кто создал заявку, второй участник — кто её забронировал
    static func draft(for request: SparringRequest,
                      bookedById: String,
                      bookedByName: String,
                      now: Date = Date()) -> MeetingClarification? {
        let authorName = request.authorFullName
        let data: [String: Any] = [
            "sparringRequestId": request.id,
            "authorId":          request.userId,
            "authorName":        authorName.isEmpty ? "Автор" : authorName,
            "bookedById":        bookedById,
            "bookedByName":      bookedByName.isEmpty ? "Партнёр" : bookedByName,
            "sparringDate":      request.date,
            "sparringTimeSlot":  request.timeSlot,
            "sparringCity":      request.city,
            "sparringLocation":  request.location,
            "status":            "active",
            "createdAt":         now,
            "updatedAt":         now
        ]
        return MeetingClarification(id: draftId(requestId: request.id), data: data)
    }
}
