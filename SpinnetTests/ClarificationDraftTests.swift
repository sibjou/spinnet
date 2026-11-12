import XCTest
@testable import Spinnet

// Черновик диалога после брони: чат открывается в один шаг, роли не перепутаны

final class ClarificationDraftTests: XCTestCase {

    private func makeRequest(authorFirst: String = "Сергей", authorLast: String = "Кузнецов") -> SparringRequest {
        SparringRequest(id: "req1", data: [
            "userId": "author1",
            "authorFirstName": authorFirst,
            "authorLastName": authorLast,
            "authorSkillLevel": "Любитель",
            "date": TestCalendar.date(2026, 10, 17, 0),
            "timeSlot": "18:00 – 20:00",
            "city": "Томск",
            "location": "Зал ТПУ",
            "status": "booked",
            "createdAt": TestCalendar.date(2026, 10, 10)
        ])!
    }

    func testDraftIdIsStable() {
        XCTAssertEqual(MeetingClarification.draftId(requestId: "req1"), "draft_req1")
    }

    func testDraftCarriesTheGame() {
        let draft = MeetingClarification.draft(for: makeRequest(), bookedById: "me", bookedByName: "Иван Петров")
        XCTAssertEqual(draft?.id, "draft_req1")
        XCTAssertEqual(draft?.sparringRequestId, "req1")
        XCTAssertEqual(draft?.sparringTimeSlot, "18:00 – 20:00")
        XCTAssertEqual(draft?.sparringCity, "Томск")
        XCTAssertEqual(draft?.sparringLocation, "Зал ТПУ")
        XCTAssertEqual(draft?.sparringDate, TestCalendar.date(2026, 10, 17, 0))
        XCTAssertEqual(draft?.status, "active")
    }

    func testRolesAreNotMixedUp() {
        let draft = MeetingClarification.draft(for: makeRequest(), bookedById: "me", bookedByName: "Иван Петров")!
        XCTAssertEqual(draft.authorId, "author1")
        XCTAssertEqual(draft.bookedById, "me")
        // Для меня партнёр — автор заявки, для автора — я
        XCTAssertEqual(draft.partnerId(currentUserId: "me"), "author1")
        XCTAssertEqual(draft.partnerName(currentUserId: "me"), "Сергей Кузнецов")
        XCTAssertEqual(draft.partnerId(currentUserId: "author1"), "me")
        XCTAssertEqual(draft.partnerName(currentUserId: "author1"), "Иван Петров")
    }

    func testEmptyNamesGetPlaceholders() {
        let draft = MeetingClarification.draft(for: makeRequest(authorFirst: "", authorLast: ""),
                                               bookedById: "me", bookedByName: "")!
        XCTAssertEqual(draft.authorName, "Автор")
        XCTAssertEqual(draft.bookedByName, "Партнёр")
    }

    func testDraftStartsWithoutUnreadOrActions() {
        let draft = MeetingClarification.draft(for: makeRequest(), bookedById: "me", bookedByName: "Иван")!
        XCTAssertEqual(draft.unreadCount(for: "me"), 0)
        XCTAssertEqual(draft.unreadCount(for: "author1"), 0)
        XCTAssertNil(draft.lastActionAt)
        XCTAssertFalse(draft.hasCoordinates)
    }
}
