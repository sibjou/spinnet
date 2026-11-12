import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Удаление аккаунта
// Порядок такой: проверить пароль → убрать за собой данные → удалить вход.
// Пароль проверяется первым: повторный вход нужен Firebase для удаления, и если пароль неверный,
// ничего ещё не тронуто. Данные чистятся в меру возможностей телефона (правила базы разрешают
// каждому менять только своё). Полная очистка «на стороне сервера» появится вместе с серверной частью.
//
// Что остаётся: матчи (в них только идентификаторы), сообщения в чатах собеседников.
// Имена в заявках, отзывах и диалогах заменяются на «Удалённый пользователь».

final class AccountDeletionService {

    private let db = Firestore.firestore()
    private let sparring = SparringService()

    /// Сколько записей за один пакет (в Firestore предел — 500)
    nonisolated private static let batchSize = 400

    /// `completion(nil)` — аккаунт удалён, иначе — текст ошибки для человека
    func delete(password: String, authService: AuthService, completion: @escaping (String?) -> Void) {
        guard ConnectionMonitor.shared.isOnline else {
            completion(ConnectionRule.actionRejected)
            return
        }
        guard let user = Auth.auth().currentUser, let email = user.email else {
            completion("Не удалось определить аккаунт. Выйдите, войдите снова и повторите.")
            return
        }
        let userId = user.uid

        // 1. Пароль. Заодно это «свежий вход», без которого Firebase не удалит аккаунт
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        user.reauthenticate(with: credential) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    completion(AccountDeletionRules.message(forAuthErrorCode: (error as NSError).code))
                    return
                }
                // 2. Организатору с открытыми турнирами удаление не даём: участники остались бы без организатора
                self?.openTournamentsCount(userId: userId) { count in
                    if count > 0 {
                        completion(AccountDeletionRules.blockedByTournaments(count: count))
                        return
                    }
                    // 3. Данные
                    self?.cleanUp(userId: userId) { profileError in
                        if let profileError {
                            completion(profileError)
                            return
                        }
                        // 4. Сам вход
                        user.delete { error in
                            DispatchQueue.main.async {
                                if let error {
                                    completion(AccountDeletionRules.message(forAuthErrorCode: (error as NSError).code))
                                    return
                                }
                                authService.logout()
                                completion(nil)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Турниры

    private func openTournamentsCount(userId: String, then done: @escaping (Int) -> Void) {
        db.collection("tournaments")
            .whereField("organizerId", isEqualTo: userId)
            .getDocuments { snapshot, _ in
                let count = snapshot?.documents.filter {
                    AccountDeletionRules.isOpenTournament(status: $0.data()["status"] as? String ?? "")
                }.count ?? 0
                DispatchQueue.main.async { done(count) }
            }
    }

    // MARK: - Данные

    private func cleanUp(userId: String, completion: @escaping (String?) -> Void) {
        // Отметка «в сети» больше не нужна и не должна пересоздать профиль
        PresenceService.shared.goOffline(userId: userId)

        let anonymous = AccountDeletionRules.anonymousName
        let steps: [(@escaping () -> Void) -> Void] = [
            // Игры с партнёрами отменяются так же, как кнопкой «Отменить»: партнёр получит уведомление
            { [self] next in cancelGames(userId: userId, then: next) },
            // Заявки, на которые никто не ответил, удаляются
            { [self] next in
                apply(db.collection("sparring_requests")
                        .whereField("userId", isEqualTo: userId)
                        .whereField("status", isEqualTo: "active"),
                      write: { batch, ref in batch.deleteDocument(ref) }, then: next)
            },
            // В остальных заявках имя заменяется
            { [self] next in
                apply(db.collection("sparring_requests").whereField("userId", isEqualTo: userId),
                      write: { batch, ref in
                          batch.updateData(["authorFirstName": anonymous, "authorLastName": ""], forDocument: ref)
                      }, then: next)
            },
            { [self] next in
                apply(db.collection("reviews").whereField("fromUserId", isEqualTo: userId),
                      write: { batch, ref in batch.updateData(["fromUserName": anonymous], forDocument: ref) },
                      then: next)
            },
            { [self] next in
                apply(db.collection("meeting_clarifications").whereField("authorId", isEqualTo: userId),
                      write: { batch, ref in batch.updateData(["authorName": anonymous], forDocument: ref) },
                      then: next)
            },
            { [self] next in
                apply(db.collection("meeting_clarifications").whereField("bookedById", isEqualTo: userId),
                      write: { batch, ref in batch.updateData(["bookedByName": anonymous], forDocument: ref) },
                      then: next)
            },
            // Запись на чужие турниры снимается
            { [self] next in leaveTournaments(userId: userId, then: next) },
            { [self] next in
                apply(db.collection("notifications").document(userId).collection("items"),
                      write: { batch, ref in batch.deleteDocument(ref) }, then: next)
            },
            { [self] next in
                apply(db.collection("blocks").document(userId).collection("blockedUsers"),
                      write: { batch, ref in batch.deleteDocument(ref) }, then: next)
            }
        ]

        run(steps, index: 0) { [self] in
            // Последним уходит профиль: пока он есть, остальные шаги могут читать имя и права
            db.collection("users").document(userId).delete { error in
                DispatchQueue.main.async {
                    if let error {
                        debugLog("Удаление аккаунта: профиль не удалён (\(error.localizedDescription))")
                        completion("Не удалось удалить данные профиля. Попробуйте позже.")
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }

    /// Шаги идут по очереди; ошибка одного шага не останавливает остальные (данные чистятся в меру сил)
    private func run(_ steps: [(@escaping () -> Void) -> Void], index: Int, then done: @escaping () -> Void) {
        guard index < steps.count else {
            done()
            return
        }
        let step = steps[index]
        step { [weak self] in
            DispatchQueue.main.async {
                self?.run(steps, index: index + 1, then: done)
            }
        }
    }

    // MARK: - Пакетные записи

    /// Применяет запись к каждому документу запроса пакетами
    private func apply(_ query: Query,
                       write: @escaping (WriteBatch, DocumentReference) -> Void,
                       then next: @escaping () -> Void) {
        query.getDocuments { [weak self] snapshot, error in
            if let error {
                debugLog("Удаление аккаунта: запрос не выполнен (\(error.localizedDescription))")
            }
            guard let self, let documents = snapshot?.documents, !documents.isEmpty else {
                next()
                return
            }
            let references = documents.map { $0.reference }
            let group = DispatchGroup()
            for chunk in PartnerNames.chunks(references, size: Self.batchSize) {
                let batch = self.db.batch()
                chunk.forEach { write(batch, $0) }
                group.enter()
                batch.commit { error in
                    if let error {
                        debugLog("Удаление аккаунта: пакет не записан (\(error.localizedDescription))")
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) { next() }
        }
    }

    // MARK: - Игры

    private func cancelGames(userId: String, then next: @escaping () -> Void) {
        let statuses = ["booked", "in_progress"]
        db.collection("sparring_requests")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", in: statuses)
            .getDocuments { [weak self] first, _ in
                let asAuthor = first?.documents.map { $0.documentID } ?? []
                guard let self else { next(); return }
                self.db.collection("sparring_requests")
                    .whereField("bookedBy", isEqualTo: userId)
                    .whereField("status", in: statuses)
                    .getDocuments { [weak self] second, _ in
                        let asPartner = second?.documents.map { $0.documentID } ?? []
                        DispatchQueue.main.async {
                            self?.cancelOneByOne(asAuthor + asPartner, index: 0, then: next)
                        }
                    }
            }
    }

    private func cancelOneByOne(_ ids: [String], index: Int, then next: @escaping () -> Void) {
        guard index < ids.count else {
            next()
            return
        }
        sparring.cancelBooking(requestId: ids[index]) { [weak self] _ in
            self?.cancelOneByOne(ids, index: index + 1, then: next)
        }
    }

    // MARK: - Турниры

    private func leaveTournaments(userId: String, then next: @escaping () -> Void) {
        db.collection("tournaments")
            .whereField("participants", arrayContains: userId)
            .getDocuments { snapshot, _ in
                let open = snapshot?.documents.filter {
                    AccountDeletionRules.isOpenTournament(status: $0.data()["status"] as? String ?? "")
                } ?? []
                guard !open.isEmpty else {
                    DispatchQueue.main.async { next() }
                    return
                }
                let group = DispatchGroup()
                for document in open {
                    group.enter()
                    document.reference.updateData(["participants": FieldValue.arrayRemove([userId])]) { _ in
                        group.leave()
                    }
                }
                group.notify(queue: .main) { next() }
            }
    }
}
