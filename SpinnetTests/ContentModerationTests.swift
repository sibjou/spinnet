import XCTest
@testable import Spinnet

final class ContentModerationTests: XCTestCase {

    private func isApproved(_ verdict: ContentModeration.Verdict) -> Bool {
        if case .approved = verdict { return true }
        return false
    }

    func testOrdinaryMessageIsAcceptable() {
        XCTAssertTrue(ContentModeration.isAcceptableMessage("Привет! Играем в 19:00, жду у входа"))
        XCTAssertTrue(ContentModeration.isAcceptableMessage(""))
    }

    func testAbuseAndThreatsAreRejectedInMessages() {
        XCTAssertFalse(ContentModeration.isAcceptableMessage("Ты сука"))
        XCTAssertFalse(ContentModeration.isAcceptableMessage("УБЬЮ тебя на корте"))
    }

    func testMessagesMayMentionMessengersUnlikeReviews() {
        let text = "Пиши в телеграм, там удобнее договориться"
        XCTAssertTrue(ContentModeration.isAcceptableMessage(text))
        XCTAssertFalse(isApproved(ContentModeration.process(text).verdict))
    }

    func testReviewsStillHidePersonalData() {
        let result = ContentModeration.process("Мой номер +7 913 123 45 67")
        XCTAssertTrue(result.cleanedText.contains("[номер скрыт]"))
        XCTAssertFalse(result.cleanedText.contains("913"))
    }

    func testCleanReviewIsApproved() {
        XCTAssertTrue(isApproved(ContentModeration.process("Отличная игра, приятный партнёр").verdict))
    }
}
