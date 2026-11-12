import XCTest
@testable import Spinnet

final class MatchModelTests: XCTestCase {

    private func data(games: Any? = [["a": 11, "b": 7], ["a": 11, "b": 5]]) -> [String: Any] {
        [
            "playerAId": "A", "playerBId": "B",
            "games": games as Any,
            "bestOf": 3,
            "status": "proposed",
            "proposedBy": "A",
            "revision": 1,
            "slotMinutes": 120,
            "city": "Томск",
            "playedAt": TestCalendar.date(2026, 10, 5, 19)
        ]
    }

    func testParsesFirestoreDocument() {
        let match = Match(id: "req1", data: data())
        XCTAssertEqual(match?.id, "req1")
        XCTAssertEqual(match?.games.count, 2)
        XCTAssertEqual(match?.format, .bestOf3)
        XCTAssertEqual(match?.status, .proposed)
        XCTAssertEqual(match?.slotMinutes, 120)
        XCTAssertEqual(match?.result?.winner, .a)
    }

    func testParsesInt64Numbers() {
        var doc = data(games: [["a": Int64(11), "b": Int64(3)], ["a": Int64(11), "b": Int64(4)]])
        doc["bestOf"] = Int64(3)
        let match = Match(id: "x", data: doc)
        XCTAssertNotNil(match)
        XCTAssertTrue(match?.result != nil)
    }

    func testRejectsBrokenDocuments() {
        XCTAssertNil(Match(id: "x", data: [:]))
        XCTAssertNil(Match(id: "x", data: data(games: "oops")))
        var wrongStatus = data(); wrongStatus["status"] = "weird"
        XCTAssertNil(Match(id: "x", data: wrongStatus))
        var wrongFormat = data(); wrongFormat["bestOf"] = 4
        XCTAssertNil(Match(id: "x", data: wrongFormat))
    }

    func testGamesRoundTrip() {
        let games = [GameScore(a: 11, b: 7), GameScore(a: 9, b: 11)]
        let encoded = Match.encode(games: games)
        XCTAssertEqual(Match.decodeGames(encoded), games)
    }

    func testCountedOnlyWhenConfirmedAndValid() {
        XCTAssertTrue(makeMatch(games: [(11, 5), (11, 5), (11, 5)], status: .confirmed).isCounted)
        XCTAssertFalse(makeMatch(games: [(11, 5), (11, 5), (11, 5)], status: .proposed).isCounted)
        XCTAssertFalse(makeMatch(games: [(11, 5), (11, 5), (11, 5)], status: .disputed).isCounted)
        // подтверждён, но счёт невозможен — не считаем
        XCTAssertFalse(makeMatch(games: [(11, 10), (11, 5), (11, 5)], status: .confirmed).isCounted)
    }

    func testPerspective() {
        // A выиграл 3:1
        let match = makeMatch(games: [(11, 5), (9, 11), (11, 8), (11, 6)])
        let forA = match.perspective(of: "A")
        XCTAssertEqual(forA?.won, true)
        XCTAssertEqual(forA?.gamesWon, 3)
        XCTAssertEqual(forA?.gamesLost, 1)
        XCTAssertEqual(forA?.pointsWon, 42)
        XCTAssertEqual(forA?.pointsLost, 30)

        let forB = match.perspective(of: "B")
        XCTAssertEqual(forB?.won, false)
        XCTAssertEqual(forB?.gamesWon, 1)
        XCTAssertEqual(forB?.pointsWon, 30)

        XCTAssertNil(match.perspective(of: "C"))
        XCTAssertEqual(match.winnerId, "A")
        XCTAssertEqual(match.opponentId(of: "A"), "B")
        XCTAssertEqual(match.opponentId(of: "B"), "A")
        XCTAssertNil(match.opponentId(of: "C"))
    }

    func testGamesFromBsPointOfView() {
        let match = makeMatch(games: [(11, 5), (9, 11)])
        XCTAssertEqual(match.games(for: "B"), [GameScore(a: 5, b: 11), GameScore(a: 11, b: 9)])
        XCTAssertEqual(match.games(for: "A"), match.games)
    }

    func testResponseRules() {
        // A внёс первое предложение
        let first = makeMatch(games: [(11, 5), (11, 5), (11, 5)], status: .proposed, proposedBy: "A", revision: 1)
        XCTAssertTrue(first.awaitsResponse(from: "B"))
        XCTAssertFalse(first.awaitsResponse(from: "A"))
        XCTAssertTrue(first.canCounter(by: "B"))
        XCTAssertTrue(first.canEdit(by: "A"))
        XCTAssertFalse(first.canEdit(by: "B"))
        XCTAssertFalse(first.awaitsResponse(from: "C"))

        // B ответил своим счётом — A может только подтвердить или оспорить
        let second = makeMatch(games: [(11, 5), (11, 5), (11, 5)], status: .proposed, proposedBy: "B", revision: 2)
        XCTAssertTrue(second.awaitsResponse(from: "A"))
        XCTAssertFalse(second.canCounter(by: "A"))

        // подтверждённый и оспоренный матчи изменить нельзя
        let confirmed = makeMatch(games: [(11, 5), (11, 5), (11, 5)], status: .confirmed)
        XCTAssertFalse(confirmed.awaitsResponse(from: "B"))
        XCTAssertFalse(confirmed.canEdit(by: "A"))
        let disputed = makeMatch(games: [(11, 5), (11, 5), (11, 5)], status: .disputed)
        XCTAssertFalse(disputed.awaitsResponse(from: "B"))
    }

    func testDeciderDetection() {
        // bo5 3:2 — решающая партия
        XCTAssertTrue(makeMatch(games: [(11, 9), (9, 11), (11, 8), (8, 11), (12, 10)]).wentToDecider)
        // bo5 3:0 — нет
        XCTAssertFalse(makeMatch(games: [(11, 5), (11, 5), (11, 5)]).wentToDecider)
        // bo3 2:1 — да
        XCTAssertTrue(makeMatch(games: [(11, 5), (5, 11), (11, 9)], format: .bestOf3).wentToDecider)
    }
}

// MARK: - Несколько матчей за одну встречу
final class MeetingMatchesTests: XCTestCase {

    private let win = [(11, 5), (11, 5), (11, 5)]       // A выигрывает 3:0
    private let loss = [(5, 11), (5, 11), (5, 11)]      // B выигрывает 3:0

    func testDocumentIds() {
        XCTAssertEqual(MatchIds.documentId(requestId: "req", ordinal: 1), "req")
        XCTAssertEqual(MatchIds.documentId(requestId: "req", ordinal: 2), "req_2")
        XCTAssertEqual(MatchIds.documentId(requestId: "req", ordinal: 0), "req")
    }

    func testParsingDocumentIds() {
        XCTAssertEqual(MatchIds.parse("req").ordinal, 1)
        XCTAssertEqual(MatchIds.parse("req").requestId, "req")
        XCTAssertEqual(MatchIds.parse("req_3").ordinal, 3)
        XCTAssertEqual(MatchIds.parse("req_3").requestId, "req")
        // Подчёркивание без числа или с единицей — это просто часть названия
        XCTAssertEqual(MatchIds.parse("req_x").requestId, "req_x")
        XCTAssertEqual(MatchIds.parse("req_1").requestId, "req_1")
        XCTAssertEqual(MatchIds.parse("_2").requestId, "_2")
    }

    func testRoundTrip() {
        for ordinal in 1...MatchIds.maxPerMeeting {
            let id = MatchIds.documentId(requestId: "AbC123", ordinal: ordinal)
            XCTAssertEqual(MatchIds.parse(id).requestId, "AbC123")
            XCTAssertEqual(MatchIds.parse(id).ordinal, ordinal)
        }
    }

    func testMatchKnowsItsMeetingAndNumber() {
        let first = makeMatch(id: "req", games: win)
        let second = makeMatch(id: "req_2", games: win)
        XCTAssertEqual(first.requestId, "req")
        XCTAssertEqual(first.ordinal, 1)
        XCTAssertEqual(second.requestId, "req")
        XCTAssertEqual(second.ordinal, 2)
    }

    func testMatchesAreOrderedByNumber() {
        let meeting = MeetingMatches([makeMatch(id: "req_3", games: win), makeMatch(id: "req", games: win), makeMatch(id: "req_2", games: win)])
        XCTAssertEqual(meeting.matches.map { $0.ordinal }, [1, 2, 3])
        XCTAssertEqual(meeting.nextOrdinal, 4)
    }

    func testEmptyMeeting() {
        let meeting = MeetingMatches([])
        XCTAssertEqual(meeting.nextOrdinal, 1)
        XCTAssertTrue(meeting.canAddMatch)
        XCTAssertEqual(meeting.summary(for: "A"), .none)
    }

    func testNewMatchWaitsForThePreviousDecision() {
        let pending = MeetingMatches([makeMatch(id: "req", games: win, status: .proposed, proposedBy: "A")])
        XCTAssertFalse(pending.canAddMatch)
        let confirmed = MeetingMatches([makeMatch(id: "req", games: win)])
        XCTAssertTrue(confirmed.canAddMatch)
        let disputed = MeetingMatches([makeMatch(id: "req", games: win, status: .disputed, proposedBy: "A")])
        XCTAssertTrue(disputed.canAddMatch)
    }

    func testLimitPerMeeting() {
        let all = (1...MatchIds.maxPerMeeting).map {
            makeMatch(id: MatchIds.documentId(requestId: "req", ordinal: $0), games: win)
        }
        let full = MeetingMatches(all)
        XCTAssertTrue(full.limitReached)
        XCTAssertFalse(full.canAddMatch)
        let almost = MeetingMatches(Array(all.dropLast()))
        XCTAssertFalse(almost.limitReached)
        XCTAssertTrue(almost.canAddMatch)
    }

    func testRecordCountsOnlyConfirmedMatches() {
        let meeting = MeetingMatches([
            makeMatch(id: "req", games: win),                                           // A выиграл
            makeMatch(id: "req_2", games: loss),                                        // B выиграл
            makeMatch(id: "req_3", games: win),                                         // A выиграл
            makeMatch(id: "req_4", games: win, status: .disputed, proposedBy: "A")      // не считается
        ])
        XCTAssertEqual(meeting.record(for: "A").won, 2)
        XCTAssertEqual(meeting.record(for: "A").lost, 1)
        XCTAssertEqual(meeting.record(for: "B").won, 1)
        XCTAssertEqual(meeting.record(for: "B").lost, 2)
        XCTAssertEqual(meeting.record(for: "Z").won, 0)
    }

    func testSummaryPriorities() {
        // Партнёр ждёт моего ответа — важнее всего остального
        let waitingForMe = MeetingMatches([
            makeMatch(id: "req", games: win),
            makeMatch(id: "req_2", games: loss, status: .proposed, proposedBy: "B")
        ])
        XCTAssertEqual(waitingForMe.summary(for: "A"), .needsYourAnswer)
        XCTAssertEqual(waitingForMe.summary(for: "B"), .waitingForPartner)
        XCTAssertEqual(waitingForMe.firstAwaitingResponse(from: "A")?.ordinal, 2)
        XCTAssertNil(waitingForMe.firstAwaitingResponse(from: "B"))
    }

    func testSummaryForConfirmedMatches() {
        let single = MeetingMatches([makeMatch(id: "req", games: win)])
        XCTAssertEqual(single.summary(for: "A"), .single(gamesWon: 3, gamesLost: 0, won: true))
        XCTAssertEqual(single.summary(for: "B"), .single(gamesWon: 0, gamesLost: 3, won: false))

        let several = MeetingMatches([makeMatch(id: "req", games: win), makeMatch(id: "req_2", games: loss), makeMatch(id: "req_3", games: win)])
        XCTAssertEqual(several.summary(for: "A"), .several(matchesWon: 2, matchesLost: 1))
    }

    func testSummaryWhenOnlyDisputed() {
        let meeting = MeetingMatches([makeMatch(id: "req", games: win, status: .disputed, proposedBy: "A")])
        XCTAssertEqual(meeting.summary(for: "A"), .disputedOnly)
    }
}
