import Foundation

// MARK: - Счёт партии
// Игрок A — автор заявки, игрок B — тот, кто её забронировал.
// Ориентация счёта не зависит от того, кто его внёс.
struct GameScore: Equatable, Hashable {
    var a: Int
    var b: Int
}

// MARK: - Формат матча
enum MatchFormat: Int, CaseIterable, Identifiable {
    case bestOf3 = 3
    case bestOf5 = 5
    case bestOf7 = 7

    var id: Int { rawValue }

    /// Сколько партий нужно выиграть
    var gamesToWin: Int { rawValue / 2 + 1 }

    var title: String { "До \(gamesToWin) побед" }
}

enum MatchSide: Equatable {
    case a, b
}

// MARK: - Итог матча
struct MatchResult: Equatable {
    let gamesWonA: Int
    let gamesWonB: Int
    let pointsA: Int
    let pointsB: Int
    let winner: MatchSide

    var gamesCount: Int { gamesWonA + gamesWonB }
}

// MARK: - Проверка счёта
// Правила настольного тенниса: партия до 11 очков, при 10:10 играют до разницы в 2 очка.
// Матч идёт до N побед (bo3 / bo5 / bo7); после решающей партии играть дальше нельзя.
enum MatchScoring {

    static let pointsToWinGame = 11
    /// Защита от опечаток вроде 110:108
    static let maxPointsInGame = 40

    // MARK: Одна партия

    /// Текст ошибки или `nil`, если счёт партии возможен
    static func gameError(_ game: GameScore) -> String? {
        if game.a < 0 || game.b < 0 { return "Очки не могут быть отрицательными" }
        if game.a == game.b { return "В партии не бывает ничьей" }

        let high = max(game.a, game.b)
        let low  = min(game.a, game.b)

        if high > maxPointsInGame { return "Слишком большой счёт партии" }
        if high < pointsToWinGame { return "Партия играется до 11 очков" }

        if high == pointsToWinGame {
            return low <= 9 ? nil : "При 10:10 играют до разницы в 2 очка"
        }

        // high > 11: партия могла продолжиться только с 10:10
        if high - low == 2 { return nil }
        return low < 10
            ? "Партия заканчивается на 11 очках, если соперник набрал не больше 9"
            : "После 10:10 партия идёт до разницы ровно в 2 очка"
    }

    static func isValidGame(_ game: GameScore) -> Bool {
        gameError(game) == nil
    }

    // MARK: Весь матч

    enum Validation: Equatable {
        /// Счёт возможен, матч закончен
        case valid(MatchResult)
        /// Пока всё верно, но матч не закончен
        case incomplete(String)
        /// Ошибка в партии с номером `gameIndex` (с нуля)
        case invalid(gameIndex: Int, message: String)

        var result: MatchResult? {
            if case .valid(let result) = self { return result }
            return nil
        }

        var isValid: Bool { result != nil }
    }

    static func validate(_ games: [GameScore], format: MatchFormat) -> Validation {
        if games.isEmpty {
            return .incomplete("Введите счёт хотя бы одной партии")
        }

        let need = format.gamesToWin
        var wonA = 0, wonB = 0
        var pointsA = 0, pointsB = 0

        for (index, game) in games.enumerated() {
            if wonA == need || wonB == need {
                return .invalid(gameIndex: index, message: "Матч уже закончился, эта партия лишняя")
            }
            if let message = gameError(game) {
                return .invalid(gameIndex: index, message: message)
            }
            if game.a > game.b { wonA += 1 } else { wonB += 1 }
            pointsA += game.a
            pointsB += game.b
        }

        guard wonA == need || wonB == need else {
            return .incomplete("Матч не закончен: нужно выиграть \(need) партии")
        }

        return .valid(MatchResult(
            gamesWonA: wonA,
            gamesWonB: wonB,
            pointsA: pointsA,
            pointsB: pointsB,
            winner: wonA > wonB ? .a : .b
        ))
    }

    /// Подпись счёта по партиям: «11:7, 9:11, 11:5»
    static func gamesDescription(_ games: [GameScore]) -> String {
        games.map { "\($0.a):\($0.b)" }.joined(separator: ", ")
    }
}
