import Foundation

// MARK: - Статус матча
// proposed — счёт внесён одним игроком, второй ещё не ответил
// confirmed — оба согласны; только такие матчи попадают в статистику
// disputed — игроки не сошлись; матч не учитывается
enum MatchStatus: String {
    case proposed
    case confirmed
    case disputed
}

// MARK: - Номера матчей одной встречи
// За одну встречу можно сыграть несколько матчей, и у каждого свой счёт и своё подтверждение.
// Документ первого матча называется так же, как заявка (так было с самого начала),
// следующие — «<id заявки>_2», «_3» и так далее. Отдельных полей не нужно:
// и приложение, и правила Firestore читают номер из названия документа.
enum MatchIds {

    /// Больше матчей за одну встречу внести нельзя
    static let maxPerMeeting = 6

    static func documentId(requestId: String, ordinal: Int) -> String {
        ordinal <= 1 ? requestId : "\(requestId)_\(ordinal)"
    }

    /// id заявки и порядковый номер матча по названию документа
    static func parse(_ documentId: String) -> (requestId: String, ordinal: Int) {
        guard let underscore = documentId.lastIndex(of: "_") else { return (documentId, 1) }
        let head = String(documentId[..<underscore])
        let tail = String(documentId[documentId.index(after: underscore)...])
        guard !head.isEmpty, let number = Int(tail), number >= 2 else { return (documentId, 1) }
        return (head, number)
    }
}

// MARK: - Матч
// Документ matches/{id заявки} — первый матч встречи; следующие — matches/{id заявки}_2 …
struct Match: Identifiable, Equatable {
    let id: String
    let playerAId: String          // автор заявки
    let playerBId: String          // забронировавший
    let games: [GameScore]
    let format: MatchFormat
    let status: MatchStatus
    let proposedBy: String         // кто внёс текущую версию счёта
    let revision: Int              // 1 — первое предложение, 2 — ответное
    let confirmedBy: String?
    let playedAt: Date
    let slotMinutes: Int
    let city: String
    let createdAt: Date
    let updatedAt: Date
    let previousGames: [GameScore]?        // первая версия, если предложен другой счёт
    let previousProposedBy: String?

    // MARK: Встреча

    /// Заявка (встреча), к которой относится матч
    var requestId: String { MatchIds.parse(id).requestId }

    /// Какой по счёту матч встречи: 1, 2, 3 …
    var ordinal: Int { MatchIds.parse(id).ordinal }

    // MARK: Участники

    var playerIds: [String] { [playerAId, playerBId] }

    func involves(_ userId: String) -> Bool {
        userId == playerAId || userId == playerBId
    }

    func opponentId(of userId: String) -> String? {
        if userId == playerAId { return playerBId }
        if userId == playerBId { return playerAId }
        return nil
    }

    // MARK: Результат

    /// Результат считается из партий заново, сохранённым итогам не доверяем
    var result: MatchResult? {
        MatchScoring.validate(games, format: format).result
    }

    /// Матч учитывается в статистике
    var isCounted: Bool {
        status == .confirmed && result != nil
    }

    var winnerId: String? {
        guard let result else { return nil }
        return result.winner == .a ? playerAId : playerBId
    }

    // MARK: Действия по ролям

    /// Ответ ждут именно от этого игрока
    func awaitsResponse(from userId: String) -> Bool {
        status == .proposed && involves(userId) && proposedBy != userId
    }

    /// Предложить свой счёт можно один раз — на первое предложение
    func canCounter(by userId: String) -> Bool {
        awaitsResponse(from: userId) && revision == 1
    }

    /// Автор текущей версии может исправить её, пока второй не ответил
    func canEdit(by userId: String) -> Bool {
        status == .proposed && involves(userId) && proposedBy == userId
    }

    // MARK: Взгляд одного игрока

    struct Perspective: Equatable {
        let gamesWon: Int
        let gamesLost: Int
        let pointsWon: Int
        let pointsLost: Int
        let won: Bool
    }

    func perspective(of userId: String) -> Perspective? {
        guard involves(userId), let result else { return nil }
        let isA = userId == playerAId
        return Perspective(
            gamesWon:   isA ? result.gamesWonA : result.gamesWonB,
            gamesLost:  isA ? result.gamesWonB : result.gamesWonA,
            pointsWon:  isA ? result.pointsA   : result.pointsB,
            pointsLost: isA ? result.pointsB   : result.pointsA,
            won:        (result.winner == .a) == isA
        )
    }

    /// Партии с точки зрения игрока: «свои» очки слева
    func games(for userId: String) -> [GameScore] {
        userId == playerBId ? games.map { GameScore(a: $0.b, b: $0.a) } : games
    }

    /// Матч дошёл до решающей партии
    var wentToDecider: Bool {
        guard let result else { return false }
        let loserGames = min(result.gamesWonA, result.gamesWonB)
        return format.gamesToWin >= 2 && loserGames == format.gamesToWin - 1
    }
}

// MARK: - Сериализация
// Даты в словарях — `Date` (Firestore сам превращает их в Timestamp при записи;
// при чтении сервис заранее переводит Timestamp в Date).
extension Match {

    init?(id: String, data: [String: Any]) {
        guard
            let playerA = data["playerAId"] as? String,
            let playerB = data["playerBId"] as? String,
            let proposedBy = data["proposedBy"] as? String,
            let statusRaw = data["status"] as? String,
            let status = MatchStatus(rawValue: statusRaw),
            let games = Match.decodeGames(data["games"]),
            let formatRaw = Match.intValue(data["bestOf"]),
            let format = MatchFormat(rawValue: formatRaw)
        else { return nil }

        let now = Date()
        self.id = id
        self.playerAId = playerA
        self.playerBId = playerB
        self.games = games
        self.format = format
        self.status = status
        self.proposedBy = proposedBy
        self.revision = Match.intValue(data["revision"]) ?? 1
        self.confirmedBy = data["confirmedBy"] as? String
        self.playedAt = data["playedAt"] as? Date ?? now
        self.slotMinutes = Match.intValue(data["slotMinutes"]) ?? 0
        self.city = data["city"] as? String ?? ""
        self.createdAt = data["createdAt"] as? Date ?? now
        self.updatedAt = data["updatedAt"] as? Date ?? now
        self.previousGames = Match.decodeGames(data["previousGames"])
        self.previousProposedBy = data["previousProposedBy"] as? String
    }

    static func encode(games: [GameScore]) -> [[String: Int]] {
        games.map { ["a": $0.a, "b": $0.b] }
    }

    static func decodeGames(_ value: Any?) -> [GameScore]? {
        guard let items = value as? [[String: Any]] else { return nil }
        var games: [GameScore] = []
        for item in items {
            guard let a = intValue(item["a"]), let b = intValue(item["b"]) else { return nil }
            games.append(GameScore(a: a, b: b))
        }
        return games
    }

    static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:       return int
        case let int64 as Int64:   return Int(int64)
        case let double as Double: return Int(double)
        case let number as NSNumber: return number.intValue
        default:                   return nil
        }
    }
}


// MARK: - Матчи одной встречи
struct MeetingMatches: Equatable {

    let matches: [Match]          // по порядку: матч 1, матч 2 …

    init(_ matches: [Match]) {
        self.matches = matches.sorted { $0.ordinal < $1.ordinal }
    }

    var isEmpty: Bool { matches.isEmpty }
    var count: Int { matches.count }

    /// Номер, под которым будет записан следующий матч
    var nextOrdinal: Int { (matches.map { $0.ordinal }.max() ?? 0) + 1 }

    /// Новый матч можно начать, когда предыдущий решён (подтверждён или оспорен) и лимит не исчерпан
    var canAddMatch: Bool {
        count < MatchIds.maxPerMeeting
            && nextOrdinal <= MatchIds.maxPerMeeting
            && !matches.contains { $0.status == .proposed }
    }

    var limitReached: Bool { nextOrdinal > MatchIds.maxPerMeeting }

    /// Первый матч, на который этот игрок должен ответить
    func firstAwaitingResponse(from userId: String) -> Match? {
        matches.first { $0.awaitsResponse(from: userId) }
    }

    var confirmed: [Match] { matches.filter { $0.isCounted } }

    /// Сколько подтверждённых матчей игрок выиграл и проиграл
    func record(for userId: String) -> (won: Int, lost: Int) {
        var won = 0
        var lost = 0
        for match in confirmed {
            guard let perspective = match.perspective(of: userId) else { continue }
            if perspective.won { won += 1 } else { lost += 1 }
        }
        return (won, lost)
    }

    // MARK: Итог для отметки на карточке игры

    enum Summary: Equatable {
        case none                                           // счёта ещё нет
        case needsYourAnswer                                // партнёр внёс счёт, ждёт ответа
        case waitingForPartner                              // вы внесли счёт, ждём партнёра
        case single(gamesWon: Int, gamesLost: Int, won: Bool)
        case several(matchesWon: Int, matchesLost: Int)
        case disputedOnly
    }

    func summary(for userId: String) -> Summary {
        if firstAwaitingResponse(from: userId) != nil { return .needsYourAnswer }
        if matches.contains(where: { $0.status == .proposed }) { return .waitingForPartner }

        let counted = confirmed
        if counted.count == 1, let perspective = counted[0].perspective(of: userId) {
            return .single(gamesWon: perspective.gamesWon, gamesLost: perspective.gamesLost, won: perspective.won)
        }
        if counted.count > 1 {
            let record = record(for: userId)
            return .several(matchesWon: record.won, matchesLost: record.lost)
        }
        return matches.isEmpty ? .none : .disputedOnly
    }
}
