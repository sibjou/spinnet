import XCTest
@testable import Spinnet

// MARK: - Когда лента считается загруженной

final class FeedLoadRuleTests: XCTestCase {

    func testEmptyAnswerFromPhoneCacheIsNotAResult() {
        // Первый запуск: копия на телефоне пустая, это не «заявок нет»
        XCTAssertFalse(FeedLoadRule.countsAsLoaded(fromCache: true, isEmpty: true, hasError: false))
    }

    func testAnswerFromPhoneCacheWithRequestsIsShownAtOnce() {
        XCTAssertTrue(FeedLoadRule.countsAsLoaded(fromCache: true, isEmpty: false, hasError: false))
    }

    func testServerAnswerCountsEvenWhenThereAreNoRequests() {
        // Сервер сказал, что заявок нет, — это правда, можно показывать пустую ленту
        XCTAssertTrue(FeedLoadRule.countsAsLoaded(fromCache: false, isEmpty: true, hasError: false))
        XCTAssertTrue(FeedLoadRule.countsAsLoaded(fromCache: false, isEmpty: false, hasError: false))
    }

    func testUnknownSourceDoesNotBlockTheFeed() {
        XCTAssertTrue(FeedLoadRule.countsAsLoaded(fromCache: nil, isEmpty: true, hasError: false))
    }

    func testErrorStopsTheWaiting() {
        XCTAssertTrue(FeedLoadRule.countsAsLoaded(fromCache: true, isEmpty: true, hasError: true))
        XCTAssertTrue(FeedLoadRule.countsAsLoaded(fromCache: nil, isEmpty: true, hasError: true))
    }

    func testWeGiveUpWaitingOnlyAfterTheHintsAppeared() {
        XCTAssertGreaterThan(FeedLoadRule.giveUpAfter, LoadingHint.verySlowAfter)
    }
}

// MARK: - Подсказка под анимацией

final class LoadingHintTests: XCTestCase {

    func testNoHintAtFirst() {
        XCTAssertNil(LoadingHint.text(waited: 0))
        XCTAssertNil(LoadingHint.text(waited: LoadingHint.slowAfter - 0.1))
        XCTAssertNil(LoadingHint.text(waited: -5))
    }

    func testSlowConnectionHintAppears() {
        let first = LoadingHint.text(waited: LoadingHint.slowAfter)
        XCTAssertNotNil(first)
        XCTAssertEqual(first, LoadingHint.text(waited: LoadingHint.verySlowAfter - 0.1))
    }

    func testLongWaitHintIsDifferentAndStays() {
        let slow = LoadingHint.text(waited: LoadingHint.slowAfter)
        let long = LoadingHint.text(waited: LoadingHint.verySlowAfter)
        XCTAssertNotNil(long)
        XCTAssertNotEqual(slow, long)
        XCTAssertEqual(long, LoadingHint.text(waited: 600))
    }
}

// MARK: - Движение мячика

final class RallyMotionTests: XCTestCase {

    private let crossing = RallyMotion.crossingDuration

    func testBallStartsAtTheLeftPaddleOnTheTable() {
        let frame = RallyMotion.frame(at: 0)
        XCTAssertEqual(frame.x, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.height, 0, accuracy: 1e-9)
        XCTAssertTrue(frame.movingRight)
        XCTAssertEqual(frame.leftSwing, 1, accuracy: 1e-9)
        XCTAssertEqual(frame.rightSwing, 0)
    }

    func testBallIsHighestOverTheNet() {
        let frame = RallyMotion.frame(at: crossing / 2)
        XCTAssertEqual(frame.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(frame.height, 1, accuracy: 1e-9)
    }

    func testBallReachesTheRightPaddleAndComesBack() {
        let hit = RallyMotion.frame(at: crossing)
        XCTAssertEqual(hit.x, 1, accuracy: 1e-9)
        XCTAssertFalse(hit.movingRight)
        XCTAssertEqual(hit.rightSwing, 1, accuracy: 1e-9)
        XCTAssertEqual(hit.leftSwing, 0)

        let back = RallyMotion.frame(at: crossing * 1.5)
        XCTAssertEqual(back.x, 0.5, accuracy: 1e-9)
        XCTAssertFalse(back.movingRight)

        let again = RallyMotion.frame(at: crossing * 2)
        XCTAssertEqual(again.x, 0, accuracy: 1e-9)
        XCTAssertTrue(again.movingRight)
    }

    func testBallDoesNotJumpWhenDirectionChanges() {
        let before = RallyMotion.frame(at: crossing - 0.001)
        let after = RallyMotion.frame(at: crossing + 0.001)
        XCTAssertEqual(before.x, after.x, accuracy: 0.01)
        XCTAssertEqual(before.height, after.height, accuracy: 0.01)
    }

    func testPaddleSwingFadesOutAfterTheHit() {
        let justAfter = RallyMotion.frame(at: crossing * 0.1)
        let later = RallyMotion.frame(at: crossing * RallyMotion.swingShare)
        XCTAssertGreaterThan(justAfter.leftSwing, 0)
        XCTAssertLessThan(justAfter.leftSwing, 1)
        XCTAssertEqual(later.leftSwing, 0, accuracy: 1e-9)
        XCTAssertEqual(RallyMotion.frame(at: crossing * 0.6).leftSwing, 0)
    }

    func testEverythingStaysInRangeAndOnlyOnePaddleSwingsAtATime() {
        var time = 0.0
        while time < 12 {
            let frame = RallyMotion.frame(at: time)
            XCTAssertTrue((0...1).contains(frame.x), "x при \(time)")
            XCTAssertTrue((0...1).contains(frame.height), "высота при \(time)")
            XCTAssertTrue((0...1).contains(frame.leftSwing), "левая при \(time)")
            XCTAssertTrue((0...1).contains(frame.rightSwing), "правая при \(time)")
            XCTAssertTrue(frame.leftSwing == 0 || frame.rightSwing == 0, "обе ракетки при \(time)")
            time += 0.013
        }
    }

    func testMotionRepeatsEveryTwoFlights() {
        for time in stride(from: 0.0, to: 2.0, by: 0.17) {
            let first = RallyMotion.frame(at: time)
            let next = RallyMotion.frame(at: time + crossing * 2)
            XCTAssertEqual(first.x, next.x, accuracy: 1e-6)
            XCTAssertEqual(first.height, next.height, accuracy: 1e-6)
            XCTAssertEqual(first.movingRight, next.movingRight)
        }
    }

    func testNegativeAndBrokenTimeAreTreatedAsTheStart() {
        let start = RallyMotion.frame(at: 0)
        XCTAssertEqual(RallyMotion.frame(at: -3), start)
        XCTAssertEqual(RallyMotion.frame(at: .nan), start)
        XCTAssertEqual(RallyMotion.frame(at: .infinity), start)
    }

    func testVeryLongSessionStillWorks() {
        // Приложение открыто сутки
        let frame = RallyMotion.frame(at: 86_400)
        XCTAssertTrue((0...1).contains(frame.x))
        XCTAssertTrue((0...1).contains(frame.height))
    }

    func testRestingFrameIsCalm() {
        let frame = RallyMotion.Frame.resting
        XCTAssertEqual(frame.leftSwing, 0)
        XCTAssertEqual(frame.rightSwing, 0)
        XCTAssertTrue((0...1).contains(frame.x))
        XCTAssertTrue((0...1).contains(frame.height))
    }
}

// MARK: - Числа для слоёв Core Animation

final class RallyKeyframesTests: XCTestCase {

    func testCycleIsThereAndBack() {
        XCTAssertEqual(RallyMotion.cycleDuration, RallyMotion.crossingDuration * 2, accuracy: 1e-12)
    }

    func testArcStartsAndEndsOnThePaddlesAndPeaksInTheMiddle() {
        let arc = RallyMotion.arcHeights(segments: 20)
        XCTAssertEqual(arc.count, 21)
        XCTAssertEqual(arc.first!, 0, accuracy: 1e-12)
        XCTAssertEqual(arc.last!, 0, accuracy: 1e-12)
        XCTAssertEqual(arc[10], 1, accuracy: 1e-12)
        XCTAssertTrue(arc.allSatisfy { (0...1).contains($0) })
    }

    func testArcIsSymmetricSoBothDirectionsLookTheSame() {
        let arc = RallyMotion.arcHeights(segments: 20)
        for index in arc.indices {
            XCTAssertEqual(arc[index], arc[arc.count - 1 - index], accuracy: 1e-12)
        }
    }

    func testArcMatchesTheFrameFormula() {
        let segments = 16
        let arc = RallyMotion.arcHeights(segments: segments)
        for index in arc.indices {
            let time = RallyMotion.crossingDuration * Double(index) / Double(segments)
            // На самой ракетке перелёт заканчивается и начинается следующий: высота там 0 в обоих случаях
            let frame = RallyMotion.frame(at: time == RallyMotion.crossingDuration ? 0 : time)
            XCTAssertEqual(arc[index], frame.height, accuracy: 1e-9)
        }
    }

    func testTooFewSegmentsStillGiveAnArc() {
        XCTAssertEqual(RallyMotion.arcHeights(segments: 0).count, 3)
        XCTAssertEqual(RallyMotion.arcHeights(segments: -4).count, 3)
    }

    /// Значение ключевых кадров в момент `fraction` (доля цикла): линейно между соседними точками
    private func interpolate(_ keyframes: RallyMotion.SwingKeyframes, at fraction: Double) -> Double {
        for index in 1..<keyframes.times.count where fraction <= keyframes.times[index] {
            let t0 = keyframes.times[index - 1], t1 = keyframes.times[index]
            let v0 = keyframes.values[index - 1], v1 = keyframes.values[index]
            return t1 == t0 ? v1 : v0 + (v1 - v0) * (fraction - t0) / (t1 - t0)
        }
        return keyframes.values.last!
    }

    func testKeyframeTimesAreOrderedAndInsideTheCycle() {
        for paddle in [RallyMotion.Paddle.left, .right] {
            let keyframes = RallyMotion.swingKeyframes(for: paddle)
            XCTAssertEqual(keyframes.times.count, keyframes.values.count)
            XCTAssertEqual(keyframes.times.first, 0)
            XCTAssertEqual(keyframes.times.last, 1)
            XCTAssertEqual(keyframes.times, keyframes.times.sorted())
            XCTAssertTrue(keyframes.values.allSatisfy { (0...1).contains($0) })
        }
    }

    func testSwingKeyframesAgreeWithTheFrameFormula() {
        let cycle = RallyMotion.cycleDuration
        let left = RallyMotion.swingKeyframes(for: .left)
        let right = RallyMotion.swingKeyframes(for: .right)
        var fraction = 0.0
        while fraction < 1 {
            // Рядом с ударом правой ракетки замах нарастает за один кадр: там сравнивать нечего
            let nearRightHit = fraction > 0.49 && fraction < 0.5
            if !nearRightHit {
                let frame = RallyMotion.frame(at: fraction * cycle)
                XCTAssertEqual(interpolate(left, at: fraction), frame.leftSwing, accuracy: 1e-6, "левая при \(fraction)")
                XCTAssertEqual(interpolate(right, at: fraction), frame.rightSwing, accuracy: 1e-6, "правая при \(fraction)")
            }
            fraction += 0.007
        }
    }

    func testLeftPaddleHitsAtTheStartAndRightOneInTheMiddle() {
        XCTAssertEqual(RallyMotion.swingKeyframes(for: .left).values.first, 1)
        let right = RallyMotion.swingKeyframes(for: .right)
        XCTAssertEqual(interpolate(right, at: 0.5), 1, accuracy: 1e-9)
        XCTAssertEqual(interpolate(right, at: 0.25), 0, accuracy: 1e-9)
    }

    func testShadowShrinksAndFadesAsTheBallRises() {
        XCTAssertEqual(RallyMotion.shadowScale(lift: 0), 1, accuracy: 1e-12)
        XCTAssertEqual(RallyMotion.shadowOpacity(lift: 0), 0.22, accuracy: 1e-12)
        XCTAssertLessThan(RallyMotion.shadowScale(lift: 1), RallyMotion.shadowScale(lift: 0))
        XCTAssertLessThan(RallyMotion.shadowOpacity(lift: 1), RallyMotion.shadowOpacity(lift: 0))
        XCTAssertGreaterThan(RallyMotion.shadowScale(lift: 1), 0)
        XCTAssertGreaterThan(RallyMotion.shadowOpacity(lift: 1), 0)
    }
}

// MARK: - Заставка при запуске

final class StartupGateTests: XCTestCase {

    func testSplashOutlivesTheFeedWaitingForTheServer() {
        // Сначала лента сдаётся сама (показывает то, что есть), потом уходит заставка
        XCTAssertGreaterThan(StartupGate.maxWait, FeedLoadRule.giveUpAfter)
    }

    func testInterfaceIsBuiltRightAfterTheFirstFrameNotLater() {
        XCTAssertGreaterThan(StartupGate.buildDelay, 0)
        XCTAssertLessThan(StartupGate.buildDelay, 0.5)
    }
}
