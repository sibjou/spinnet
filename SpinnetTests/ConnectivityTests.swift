import XCTest
@testable import Spinnet

// MARK: - Решение перед записью

final class WriteGateTests: XCTestCase {

    func testWithNetworkTheWriteIsSent() {
        XCTAssertEqual(WriteGate.decide(isOnline: true), .send)
    }

    func testWithoutNetworkTheWriteIsRejectedWithAnExplanation() {
        XCTAssertEqual(WriteGate.decide(isOnline: false), .reject(message: ConnectionRule.actionRejected))
    }

    func testMessagesAreFilledAndSayAboutTheInternet() {
        XCTAssertTrue(ConnectionRule.offlineStatus.contains("интернета"))
        XCTAssertTrue(ConnectionRule.actionRejected.contains("интернета"))
        XCTAssertTrue(ConnectionRule.actionRejected.contains("не выполнено"))
        XCTAssertGreaterThan(ConnectionRule.noticeDuration, 0)
    }

    func testShortDropoutsAreNotShown() {
        XCTAssertGreaterThan(ConnectionRule.offlineGrace, 0)
        XCTAssertLessThan(ConnectionRule.offlineGrace, ConnectionRule.noticeDuration)
    }
}

// MARK: - Состояние связи

final class ConnectionStateTests: XCTestCase {

    func testStartsOnlineSoThereIsNoFlashOfOfflineText() {
        let state = ConnectionState()
        XCTAssertTrue(state.isOnline)
        XCTAssertNil(state.notice)
        XCTAssertEqual(state.gate(), .send)
    }

    func testSameStatusChangesNothing() {
        var state = ConnectionState()
        XCTAssertEqual(state.update(isOnline: true), .none)
        _ = state.update(isOnline: false)
        XCTAssertEqual(state.update(isOnline: false), .none)
        XCTAssertFalse(state.isOnline)
    }

    func testGoingOfflineAndBack() {
        var state = ConnectionState()
        XCTAssertEqual(state.update(isOnline: false), .wentOffline)
        XCTAssertFalse(state.isOnline)
        XCTAssertEqual(state.gate(), .reject(message: ConnectionRule.actionRejected))

        XCTAssertEqual(state.update(isOnline: true), .cameOnline)
        XCTAssertTrue(state.isOnline)
        XCTAssertEqual(state.gate(), .send)
    }

    func testNoticeIsShownAndThenCleared() {
        var state = ConnectionState()
        let token = state.show("Текст")
        XCTAssertEqual(state.notice, "Текст")
        state.clearNotice(token: token)
        XCTAssertNil(state.notice)
    }

    func testOldTimerDoesNotRemoveANewerNotice() {
        var state = ConnectionState()
        let first = state.show("Первое")
        let second = state.show("Второе")
        XCTAssertNotEqual(first, second)

        state.clearNotice(token: first)
        XCTAssertEqual(state.notice, "Второе", "таймер первого пояснения не должен убирать второе")

        state.clearNotice(token: second)
        XCTAssertNil(state.notice)
    }

    func testNoticeDisappearsWhenTheNetworkReturns() {
        var state = ConnectionState()
        _ = state.update(isOnline: false)
        _ = state.show(ConnectionRule.actionRejected)
        _ = state.update(isOnline: true)
        XCTAssertNil(state.notice)
    }

    func testClearingWithAStaleTokenAfterReturnIsHarmless() {
        var state = ConnectionState()
        _ = state.update(isOnline: false)
        let token = state.show("Текст")
        _ = state.update(isOnline: true)
        state.clearNotice(token: token)
        XCTAssertNil(state.notice)
        XCTAssertTrue(state.isOnline)
    }

    // MARK: Какой экран показывает пояснение

    func testNoHostMeansNobodyShows() {
        XCTAssertNil(ConnectionState().topHost)
    }

    func testTheLatestScreenShowsTheNotice() {
        var state = ConnectionState()
        let root = UUID(), sheet = UUID()
        state.register(host: root)
        XCTAssertEqual(state.topHost, root)
        state.register(host: sheet)
        XCTAssertEqual(state.topHost, sheet, "лист поверх экрана показывает пояснение сам")
    }

    func testClosingTheSheetReturnsTheNoticeToTheScreenBelow() {
        var state = ConnectionState()
        let root = UUID(), sheet = UUID()
        state.register(host: root)
        state.register(host: sheet)
        state.unregister(host: sheet)
        XCTAssertEqual(state.topHost, root)
        state.unregister(host: root)
        XCTAssertNil(state.topHost)
    }

    func testRegisteringTwiceDoesNotDuplicate() {
        var state = ConnectionState()
        let root = UUID(), sheet = UUID()
        state.register(host: root)
        state.register(host: sheet)
        state.register(host: root)
        XCTAssertEqual(state.hosts, [sheet, root])
        state.unregister(host: root)
        XCTAssertEqual(state.topHost, sheet)
    }

    func testUnregisteringAnUnknownScreenIsHarmless() {
        var state = ConnectionState()
        state.register(host: UUID())
        let before = state
        state.unregister(host: UUID())
        XCTAssertEqual(state, before)
    }
}
