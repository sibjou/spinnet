import XCTest
@testable import Spinnet

final class AccountDeletionRulesTests: XCTestCase {

    func testWrongPasswordCodes() {
        XCTAssertEqual(AccountDeletionRules.message(forAuthErrorCode: 17009), "Неверный пароль")
        XCTAssertEqual(AccountDeletionRules.message(forAuthErrorCode: 17004), "Неверный пароль")
    }

    func testNetworkAndRateLimit() {
        XCTAssertTrue(AccountDeletionRules.message(forAuthErrorCode: 17020).contains("интернет"))
        XCTAssertTrue(AccountDeletionRules.message(forAuthErrorCode: 17010).contains("Слишком много"))
    }

    func testUnknownCodeStillExplains() {
        XCTAssertFalse(AccountDeletionRules.message(forAuthErrorCode: 99999).isEmpty)
    }

    func testTournamentsWord() {
        XCTAssertEqual(AccountDeletionRules.tournamentsWord(1), "турнир")
        XCTAssertEqual(AccountDeletionRules.tournamentsWord(2), "турнира")
        XCTAssertEqual(AccountDeletionRules.tournamentsWord(5), "турниров")
        XCTAssertEqual(AccountDeletionRules.tournamentsWord(11), "турниров")
        XCTAssertEqual(AccountDeletionRules.tournamentsWord(21), "турнир")
        XCTAssertEqual(AccountDeletionRules.tournamentsWord(24), "турнира")
    }

    func testBlockedMessageHasCount() {
        XCTAssertTrue(AccountDeletionRules.blockedByTournaments(count: 3).contains("3 турнира"))
    }

    func testOpenTournamentStatuses() {
        XCTAssertTrue(AccountDeletionRules.isOpenTournament(status: "upcoming"))
        XCTAssertTrue(AccountDeletionRules.isOpenTournament(status: "in_progress"))
        XCTAssertFalse(AccountDeletionRules.isOpenTournament(status: "completed"))
        XCTAssertFalse(AccountDeletionRules.isOpenTournament(status: ""))
    }

    func testPasswordRequired() {
        XCTAssertFalse(AccountDeletionRules.canSubmit(password: ""))
        XCTAssertTrue(AccountDeletionRules.canSubmit(password: "x"))
    }

    func testConsequencesAreListed() {
        XCTAssertGreaterThanOrEqual(AccountDeletionRules.consequences.count, 3)
        XCTAssertFalse(AccountDeletionRules.anonymousName.isEmpty)
    }
}
