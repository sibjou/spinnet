import XCTest
@testable import Spinnet

final class NotificationTextsTests: XCTestCase {

    func testCancellationByPartnerNamesWhoLeftAndKeepsRequestOpen() {
        let copy = NotificationTexts.cancellation(name: "Иван Петров", byAuthor: false, when: "19 октября, 18:00 – 20:00")
        XCTAssertEqual(copy.title, "Партнёр отказался от игры")
        XCTAssertTrue(copy.body.contains("Иван Петров"))
        XCTAssertTrue(copy.body.contains("19 октября, 18:00 – 20:00"))
        XCTAssertTrue(copy.body.contains("снова в ленте"))
    }

    func testCancellationByAuthorClosesTheGame() {
        let copy = NotificationTexts.cancellation(name: "Анна Орлова", byAuthor: true, when: "5 ноября")
        XCTAssertEqual(copy.title, "Игра отменена")
        XCTAssertTrue(copy.body.contains("Анна Орлова"))
        XCTAssertTrue(copy.body.contains("Заявка закрыта"))
    }

    func testCancellationNeverInvitesAReview() {
        // После отмены оценить игрока нельзя — текст не должен к этому звать
        let a = NotificationTexts.cancellation(name: "Иван", byAuthor: false, when: "")
        let b = NotificationTexts.cancellation(name: "Иван", byAuthor: true, when: "")
        XCTAssertFalse(a.body.lowercased().contains("оцените"))
        XCTAssertFalse(b.body.lowercased().contains("оцените"))
    }

    func testEmptyNameFallsBackToPartner() {
        let copy = NotificationTexts.cancellation(name: "  ", byAuthor: false, when: "")
        XCTAssertTrue(copy.body.hasPrefix("Партнёр отказался(ась) от игры."))
    }

    func testWhenSkipsEmptyParts() {
        XCTAssertEqual(NotificationTexts.when(dateText: "19 октября", slot: "18:00 – 20:00"), "19 октября, 18:00 – 20:00")
        XCTAssertEqual(NotificationTexts.when(dateText: "", slot: "18:00 – 20:00"), "18:00 – 20:00")
        XCTAssertEqual(NotificationTexts.when(dateText: "", slot: ""), "")
    }

    func testClarificationTexts() {
        XCTAssertEqual(NotificationTexts.clarification(from: "Иван", kind: .time("19:00 – 21:00")).body, "19:00 – 21:00")
        XCTAssertEqual(NotificationTexts.clarification(from: "Иван", kind: .late(minutes: 10)).body, "Примерно на 10 мин")
        XCTAssertEqual(NotificationTexts.clarification(from: "Иван", kind: .arrived).title, "Иван уже на месте")
        XCTAssertEqual(NotificationTexts.clarification(from: "", kind: .confirm).title, "Партнёр подтверждает встречу")
    }

    func testLongMessageIsShortened() {
        let long = String(repeating: "а", count: 300)
        let copy = NotificationTexts.clarification(from: "Иван", kind: .message(long))
        XCTAssertEqual(copy.body.count, 120)
        XCTAssertTrue(copy.body.hasSuffix("…"))
        XCTAssertEqual(NotificationTexts.shortened("  коротко  ", limit: 120), "коротко")
    }

    func testNotificationRouting() {
        XCTAssertTrue(NotificationType.cancellation.opensProfile)
        XCTAssertFalse(NotificationType.cancellation.opensGame)
        XCTAssertTrue(NotificationType.reviewReminder.opensReview)
        XCTAssertTrue(NotificationType.reviewReminder.opensGame)
        XCTAssertTrue(NotificationType.matchReminder.opensMatch)
        XCTAssertFalse(NotificationType.matchReminder.opensReview)
        XCTAssertTrue(NotificationType.clarification.opensClarification)
        XCTAssertEqual(NotificationType.clarification.category, .clarifications)
    }
}

// Колокольчик и вкладка «Чаты» не дублируют друг друга
final class NotificationBellTests: XCTestCase {

    func testChatEventsAreNotInTheBell() {
        XCTAssertFalse(NotificationType.clarification.showsInBell)
        XCTAssertFalse(NotificationType.bellRawValues.contains("clarification"))
    }

    func testAllOtherEventsAreInTheBell() {
        for type in NotificationType.allCases where type != .clarification {
            XCTAssertTrue(type.showsInBell, type.rawValue)
            XCTAssertTrue(NotificationType.bellRawValues.contains(type.rawValue), type.rawValue)
        }
        XCTAssertEqual(NotificationType.bellRawValues.count, NotificationType.allCases.count - 1)
    }

    func testBellValuesFitIntoOneQuery() {
        // В запрос «in» Firestore принимает не больше 30 значений
        XCTAssertLessThanOrEqual(NotificationType.bellRawValues.count, 30)
    }
}
