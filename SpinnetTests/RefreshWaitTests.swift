import XCTest
@testable import Spinnet

// Жест «потянуть вниз» не должен зависать, даже если сеть не отвечает

final class RefreshWaitTests: XCTestCase {

    func testReturnsWhenWorkFinishesFast() async {
        let started = Date()
        await RefreshWait.wait(timeout: 3) { finish in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { finish() }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    }

    func testReturnsByTimeoutWhenWorkNeverFinishes() async {
        let started = Date()
        await RefreshWait.wait(timeout: 0.3) { _ in /* ответа нет */ }
        let spent = Date().timeIntervalSince(started)
        XCTAssertGreaterThanOrEqual(spent, 0.25)
        XCTAssertLessThan(spent, 2.0)
    }

    func testLateFinishAfterTimeoutIsHarmless() async {
        // Ответ пришёл после того, как ожидание закончилось: второй раз продолжение не вызывается
        let box = FinishBox()
        await RefreshWait.wait(timeout: 0.1) { finish in box.finish = finish }
        box.finish?()
        box.finish?()
    }

    func testFinishCalledSeveralTimesResumesOnce() async {
        await RefreshWait.wait(timeout: 2) { finish in
            finish()
            finish()
            DispatchQueue.main.async { finish() }
        }
    }

    func testOneShotClaimsOnce() {
        let once = OneShot()
        XCTAssertTrue(once.claim())
        XCTAssertFalse(once.claim())
        XCTAssertFalse(once.claim())
    }

    func testDefaultTimeoutIsShort() {
        XCTAssertLessThanOrEqual(RefreshWait.timeout, 6)
        XCTAssertGreaterThan(RefreshWait.timeout, 0)
    }
}

private final class FinishBox: @unchecked Sendable {
    var finish: (@Sendable () -> Void)?
}
