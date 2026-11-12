import XCTest
@testable import Spinnet

final class MatchScoringTests: XCTestCase {

    // MARK: - Одна партия

    func testValidGames() {
        let valid = [(11, 0), (11, 5), (11, 9), (0, 11), (9, 11), (12, 10), (10, 12), (15, 13), (25, 23)]
        for (a, b) in valid {
            XCTAssertTrue(MatchScoring.isValidGame(GameScore(a: a, b: b)), "\(a):\(b) должен быть допустим")
        }
    }

    func testInvalidGames() {
        let invalid = [
            (11, 10),   // при 10:10 играют до разницы в 2
            (10, 11),
            (10, 8),    // меньше 11
            (0, 0),
            (11, 11),   // ничья
            (12, 9),    // партия закончилась бы на 11:9
            (13, 10),   // разница 3 после 10:10
            (-1, 11),
            (41, 39)    // выше разумного предела
        ]
        for (a, b) in invalid {
            XCTAssertFalse(MatchScoring.isValidGame(GameScore(a: a, b: b)), "\(a):\(b) должен быть недопустим")
            XCTAssertNotNil(MatchScoring.gameError(GameScore(a: a, b: b)))
        }
    }

    // MARK: - Матч

    private func games(_ pairs: [(Int, Int)]) -> [GameScore] {
        pairs.map { GameScore(a: $0.0, b: $0.1) }
    }

    func testBestOf3WinInTwoGames() {
        let result = MatchScoring.validate(games([(11, 5), (11, 7)]), format: .bestOf3).result
        XCTAssertEqual(result?.gamesWonA, 2)
        XCTAssertEqual(result?.gamesWonB, 0)
        XCTAssertEqual(result?.winner, .a)
        XCTAssertEqual(result?.pointsA, 22)
        XCTAssertEqual(result?.pointsB, 12)
    }

    func testBestOf3WinInThreeGames() {
        let result = MatchScoring.validate(games([(9, 11), (11, 8), (5, 11)]), format: .bestOf3).result
        XCTAssertEqual(result?.winner, .b)
        XCTAssertEqual(result?.gamesWonA, 1)
        XCTAssertEqual(result?.gamesWonB, 2)
    }

    func testBestOf5AndBestOf7() {
        let bo5 = games([(11, 1), (11, 2), (11, 3)])
        XCTAssertTrue(MatchScoring.validate(bo5, format: .bestOf5).isValid)

        let bo7 = games([(11, 1), (11, 2), (11, 3), (11, 4)])
        XCTAssertTrue(MatchScoring.validate(bo7, format: .bestOf7).isValid)
        // тот же счёт в bo5 — лишняя партия
        XCTAssertEqual(MatchScoring.validate(bo7, format: .bestOf5),
                       .invalid(gameIndex: 3, message: "Матч уже закончился, эта партия лишняя"))
    }

    func testIncompleteMatch() {
        if case .incomplete = MatchScoring.validate(games([(11, 5)]), format: .bestOf3) {} else {
            XCTFail("Матч не закончен — ожидали .incomplete")
        }
        if case .incomplete = MatchScoring.validate([], format: .bestOf5) {} else {
            XCTFail("Пустой счёт — ожидали .incomplete")
        }
    }

    func testExtraGameAfterDecidedIsRejected() {
        let validation = MatchScoring.validate(games([(11, 5), (11, 7), (11, 3)]), format: .bestOf3)
        XCTAssertEqual(validation, .invalid(gameIndex: 2, message: "Матч уже закончился, эта партия лишняя"))
    }

    func testInvalidGameInsideMatchReportsIndex() {
        let validation = MatchScoring.validate(games([(11, 5), (11, 10)]), format: .bestOf3)
        guard case .invalid(let index, _) = validation else { return XCTFail("Ожидали .invalid") }
        XCTAssertEqual(index, 1)
    }

    func testGamesToWin() {
        XCTAssertEqual(MatchFormat.bestOf3.gamesToWin, 2)
        XCTAssertEqual(MatchFormat.bestOf5.gamesToWin, 3)
        XCTAssertEqual(MatchFormat.bestOf7.gamesToWin, 4)
    }

    func testGamesDescription() {
        XCTAssertEqual(MatchScoring.gamesDescription(games([(11, 7), (9, 11)])), "11:7, 9:11")
    }
}
