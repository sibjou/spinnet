import Foundation
import FirebaseFirestore

// MARK: - Ошибки
enum MatchError: Int, Error {
    case invalidScore = 1
    case notParticipant
    case gameNotAvailable
    case notStarted
    case alreadyDecided
    case limitReached
    case previousNotDecided
    case changed
    case notFound
    case notAllowed
    case network
    case denied
    case unknown

    var message: String {
        switch self {
        case .invalidScore:     return "Такой счёт невозможен. Проверьте очки в партиях"
        case .notParticipant:   return "Счёт может внести только участник игры"
        case .gameNotAvailable: return "Для этой встречи нельзя внести счёт"
        case .notStarted:       return "Счёт можно внести, когда игра начнётся"
        case .alreadyDecided:   return "По этому матчу решение уже принято"
        case .limitReached:     return "За одну встречу можно внести не больше \(MatchIds.maxPerMeeting) матчей"
        case .previousNotDecided: return "Сначала подтвердите или оспорьте предыдущий матч встречи"
        case .changed:          return "Партнёр изменил счёт, пока вы смотрели. Проверьте новый вариант"
        case .notFound:         return "Матч не найден"
        case .notAllowed:       return "Это действие сейчас недоступно"
        case .network:          return "Нет связи с сервером. Проверьте интернет (в России может понадобиться VPN) и повторите"
        case .denied:           return "Нет доступа к записи счёта. Проверьте, что в Firebase опубликованы актуальные правила Firestore"
        case .unknown:          return "Не удалось сохранить. Попробуйте ещё раз"
        }
    }

    fileprivate static let domain = "Spinnet.Match"

    fileprivate var nsError: NSError {
        NSError(domain: MatchError.domain, code: rawValue, userInfo: [NSLocalizedDescriptionKey: message])
    }

    fileprivate init(_ error: NSError) {
        if error.domain == MatchError.domain, let known = MatchError(rawValue: error.code) {
            self = known
        } else if error.domain == "FIRFirestoreErrorDomain" {
            // Коды Firestore: 4 — таймаут, 7 — нет прав, 14 — сервер недоступен (нет сети)
            switch error.code {
            case 4, 14: self = .network
            case 7, 16: self = .denied
            default:    self = .unknown
            }
        } else if error.domain == NSURLErrorDomain {
            self = .network
        } else {
            self = .unknown
        }
    }
}

// MARK: - Кто выполняет действие
struct MatchActor {
    let id: String
    let name: String
}

// MARK: - MatchService
// Матч — документ matches/{id заявки} (первый матч встречи) или matches/{id заявки}_2, _3 …
// (следующие, см. MatchIds). Все изменения идут через транзакции,
// чтобы подтвердить можно было только тот счёт, который игрок реально видел.
final class MatchService {

    static let shared = MatchService()

    private let db = Firestore.firestore()
    private let allowedRequestStatuses: Set<String> = ["booked", "in_progress", "completed"]

    private init() {}

    private func matchRef(_ id: String) -> DocumentReference {
        db.collection("matches").document(id)
    }

    // MARK: - Чтение

    /// Один матч по названию документа (для первого матча оно совпадает с id заявки)
    func fetchMatch(documentId: String, completion: @escaping (Match?) -> Void) {
        matchRef(documentId).getDocument { snapshot, _ in
            let match = snapshot?.data().flatMap { Match(id: documentId, data: MatchService.plain($0)) }
            DispatchQueue.main.async { completion(match) }
        }
    }

    /// Все матчи одной встречи: документы, названия которых начинаются с id заявки
    func fetchMeetingMatches(requestId: String, completion: @escaping (MeetingMatches) -> Void) {
        db.collection("matches")
            .whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: requestId)
            .whereField(FieldPath.documentID(), isLessThan: requestId + "\u{f8ff}")
            .getDocuments { snapshot, _ in
                let matches = snapshot?.documents.compactMap { document -> Match? in
                    // Название только начинается с id заявки — отсекаем чужие документы
                    guard MatchIds.parse(document.documentID).requestId == requestId else { return nil }
                    return Match(id: document.documentID, data: MatchService.plain(document.data()))
                } ?? []
                DispatchQueue.main.async { completion(MeetingMatches(matches)) }
            }
    }

    /// Все матчи игрока в любом статусе. В статистику попадают только подтверждённые —
    /// это решает `StatsCalculator`.
    func fetchMatches(userId: String, completion: @escaping ([Match]) -> Void) {
        db.collection("matches")
            .whereField("playerIds", arrayContains: userId)
            .getDocuments { snapshot, _ in
                let matches = snapshot?.documents.compactMap {
                    Match(id: $0.documentID, data: MatchService.plain($0.data()))
                } ?? []
                DispatchQueue.main.async { completion(matches) }
            }
    }

    // MARK: - Внести счёт (или исправить свой, пока партнёр не ответил)

    func propose(requestId: String,
                 ordinal: Int = 1,
                 games: [GameScore],
                 format: MatchFormat,
                 player: MatchActor,
                 completion: @escaping (Result<Match, MatchError>) -> Void) {

        guard MatchScoring.validate(games, format: format).isValid else {
            completion(.failure(.invalidScore))
            return
        }
        guard (1...MatchIds.maxPerMeeting).contains(ordinal) else {
            completion(.failure(.limitReached))
            return
        }

        let matchId = MatchIds.documentId(requestId: requestId, ordinal: ordinal)
        let requestRef = db.collection("sparring_requests").document(requestId)
        let matchRef = self.matchRef(matchId)
        // Предыдущий матч этой же встречи (для второго и следующих)
        let previousRef: DocumentReference? = ordinal > 1
            ? self.matchRef(MatchIds.documentId(requestId: requestId, ordinal: ordinal - 1))
            : nil
        let allowed = allowedRequestStatuses

        db.runTransaction({ transaction, errorPointer -> Any? in
            let requestSnapshot: DocumentSnapshot
            let matchSnapshot: DocumentSnapshot
            var previousSnapshot: DocumentSnapshot?
            do {
                requestSnapshot = try transaction.getDocument(requestRef)
                matchSnapshot = try transaction.getDocument(matchRef)
                if let previousRef {
                    previousSnapshot = try transaction.getDocument(previousRef)
                }
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            guard let request = requestSnapshot.data() else {
                return MatchService.fail(.notFound, errorPointer)
            }
            let authorId = request["userId"] as? String ?? ""
            let bookedBy = request["bookedBy"] as? String ?? ""

            guard !bookedBy.isEmpty, player.id == authorId || player.id == bookedBy else {
                return MatchService.fail(.notParticipant, errorPointer)
            }
            guard allowed.contains(request["status"] as? String ?? "") else {
                return MatchService.fail(.gameNotAvailable, errorPointer)
            }

            let day  = (request["date"] as? Timestamp)?.dateValue() ?? Date()
            let slot = request["timeSlot"] as? String ?? ""
            let playedAt = GameSlot.startDate(day: day, slot: slot) ?? day
            guard playedAt <= Date() else {
                return MatchService.fail(.notStarted, errorPointer)
            }

            if matchSnapshot.exists {
                // Уже есть запись: править можно только свою версию, пока партнёр не ответил
                guard let data = matchSnapshot.data(),
                      let existing = Match(id: matchId, data: MatchService.plain(data)),
                      existing.canEdit(by: player.id) else {
                    return MatchService.fail(.alreadyDecided, errorPointer)
                }
                transaction.updateData([
                    "games":     Match.encode(games: games),
                    "bestOf":    format.rawValue,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: matchRef)
            } else {
                // Следующий матч встречи — только после решения по предыдущему
                if let previousSnapshot {
                    guard previousSnapshot.exists,
                          let previousData = previousSnapshot.data(),
                          let previous = Match(id: previousSnapshot.documentID, data: MatchService.plain(previousData)),
                          previous.status != .proposed else {
                        return MatchService.fail(.previousNotDecided, errorPointer)
                    }
                }
                transaction.setData([
                    "playerAId":   authorId,
                    "playerBId":   bookedBy,
                    "playerIds":   [authorId, bookedBy],
                    "games":       Match.encode(games: games),
                    "bestOf":      format.rawValue,
                    "status":      MatchStatus.proposed.rawValue,
                    "proposedBy":  player.id,
                    "revision":    1,
                    "playedAt":    playedAt,
                    "slotMinutes": GameSlot.durationMinutes(of: slot),
                    "city":        request["city"] as? String ?? "",
                    "createdAt":   FieldValue.serverTimestamp(),
                    "updatedAt":   FieldValue.serverTimestamp()
                ], forDocument: matchRef)
            }
            return nil
        }) { [weak self] _, error in
            self?.finish(matchId: matchId, error: error, completion: completion) { match in
                self?.notify(match, player: player, kind: .proposed)
            }
        }
    }

    // MARK: - Подтвердить

    func confirm(seen: Match, player: MatchActor,
                 completion: @escaping (Result<Match, MatchError>) -> Void) {
        update(seen: seen, player: player, requirement: { $0.awaitsResponse(from: player.id) },
               changes: { _ in
                   [
                       "status":      MatchStatus.confirmed.rawValue,
                       "confirmedBy": player.id,
                       "confirmedAt": FieldValue.serverTimestamp()
                   ]
               },
               completion: completion,
               afterSuccess: { [weak self] match in self?.notify(match, player: player, kind: .confirmed) })
    }

    // MARK: - Предложить свой счёт (один раз)

    func counter(seen: Match, games: [GameScore], format: MatchFormat, player: MatchActor,
                 completion: @escaping (Result<Match, MatchError>) -> Void) {
        guard MatchScoring.validate(games, format: format).isValid else {
            completion(.failure(.invalidScore))
            return
        }
        update(seen: seen, player: player, requirement: { $0.canCounter(by: player.id) },
               changes: { current in
                   [
                       "games":              Match.encode(games: games),
                       "bestOf":             format.rawValue,
                       "proposedBy":         player.id,
                       "revision":           2,
                       "previousGames":      Match.encode(games: current.games),
                       "previousProposedBy": current.proposedBy
                   ]
               },
               completion: completion,
               afterSuccess: { [weak self] match in self?.notify(match, player: player, kind: .countered) })
    }

    // MARK: - Оспорить

    func dispute(seen: Match, player: MatchActor,
                 completion: @escaping (Result<Match, MatchError>) -> Void) {
        update(seen: seen, player: player, requirement: { $0.awaitsResponse(from: player.id) },
               changes: { _ in
                   [
                       "status":     MatchStatus.disputed.rawValue,
                       "disputedBy": player.id
                   ]
               },
               completion: completion,
               afterSuccess: { [weak self] match in self?.notify(match, player: player, kind: .disputed) })
    }

    // MARK: - Общая часть ответов партнёра

    /// Меняет матч, только если он всё ещё в том виде, в котором игрок его видел
    private func update(seen: Match,
                        player: MatchActor,
                        requirement: @escaping (Match) -> Bool,
                        changes: @escaping (Match) -> [String: Any],
                        completion: @escaping (Result<Match, MatchError>) -> Void,
                        afterSuccess: @escaping (Match) -> Void) {

        let ref = matchRef(seen.id)

        db.runTransaction({ transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            guard let data = snapshot.data(),
                  let current = Match(id: seen.id, data: MatchService.plain(data)) else {
                return MatchService.fail(.notFound, errorPointer)
            }
            guard current.status == .proposed else {
                return MatchService.fail(.alreadyDecided, errorPointer)
            }
            guard requirement(current) else {
                return MatchService.fail(.notAllowed, errorPointer)
            }
            // Партнёр успел исправить счёт — подтверждать вслепую нельзя
            guard current.games == seen.games,
                  current.proposedBy == seen.proposedBy,
                  current.revision == seen.revision else {
                return MatchService.fail(.changed, errorPointer)
            }

            var fields = changes(current)
            fields["updatedAt"] = FieldValue.serverTimestamp()
            transaction.updateData(fields, forDocument: ref)
            return nil
        }) { [weak self] _, error in
            self?.finish(matchId: seen.id, error: error, completion: completion, afterSuccess: afterSuccess)
        }
    }

    // MARK: - Завершение операции

    private func finish(matchId: String,
                        error: Error?,
                        completion: @escaping (Result<Match, MatchError>) -> Void,
                        afterSuccess: @escaping (Match) -> Void) {
        if let error = error as NSError? {
            debugLog("Матч: ошибка Firestore \(error.domain) \(error.code): \(error.localizedDescription)")
            DispatchQueue.main.async { completion(.failure(MatchError(error))) }
            return
        }
        // Перечитываем документ: серверные даты теперь проставлены
        fetchMatch(documentId: matchId) { match in
            guard let match else {
                completion(.failure(.notFound))
                return
            }
            NotificationService.shared.cancelMatchReminder(sparringRequestId: match.requestId)
            afterSuccess(match)
            completion(.success(match))
        }
    }

    // MARK: - Уведомления партнёру

    enum NoticeKind {
        case proposed, confirmed, countered, disputed
    }

    private func notify(_ match: Match, player: MatchActor, kind: NoticeKind) {
        guard let recipient = match.opponentId(of: player.id) else { return }

        // Счёт — глазами получателя: сначала его очки
        let score: String
        if let p = match.perspective(of: recipient) {
            score = "\(p.gamesWon):\(p.gamesLost)"
        } else {
            score = ""
        }
        let name = player.name.isEmpty ? "Партнёр" : player.name
        // Для второго и следующих матчей встречи называем номер
        let matchLabel = match.ordinal > 1 ? "Матч \(match.ordinal). " : ""

        let title: String
        let body: String
        let type: NotificationType
        switch kind {
        case .proposed:
            type  = .matchProposed
            title = "Внесён счёт игры 🏓"
            body  = "\(matchLabel)\(name): \(score). Проверьте и подтвердите или внесите свой счёт"
        case .countered:
            type  = .matchCountered
            title = "Предложен другой счёт"
            body  = "\(matchLabel)\(name) предлагает счёт \(score). Подтвердите его или оспорьте"
        case .confirmed:
            type  = .matchConfirmed
            title = "Счёт подтверждён ✅"
            body  = "\(matchLabel)Результат игры с \(name) — \(score) — подтверждён и учтён в статистике"
        case .disputed:
            type  = .matchDisputed
            title = "Счёт оспорен"
            body  = "\(matchLabel)\(name) не согласен(на) со счётом. Матч не учитывается в статистике"
        }

        NotificationService.shared.saveAndPush(
            userId: recipient,
            type: type,
            title: title,
            body: body,
            targetType: "game",
            targetId: match.requestId
        )
    }

    // MARK: - Вспомогательное

    /// Timestamp → Date, чтобы модель `Match` не зависела от Firebase
    static func plain(_ data: [String: Any]) -> [String: Any] {
        var result = data
        for (key, value) in data {
            if let timestamp = value as? Timestamp {
                result[key] = timestamp.dateValue()
            }
        }
        return result
    }

    private static func fail(_ error: MatchError, _ pointer: NSErrorPointer) -> Any? {
        pointer?.pointee = error.nsError
        return nil
    }
}
