import XCTest
@testable import Spinnet

final class RegistrationRulesTests: XCTestCase {

    func testEmailShapes() {
        XCTAssertTrue(RegistrationRules.looksLikeEmail("a@b.ru"))
        XCTAssertTrue(RegistrationRules.looksLikeEmail("  name.surname+tag@mail.example.com "))
        for bad in ["", "abc", "a@b", "@b.ru", "a@", "a@@b.ru", "a b@c.ru", "a@b.", "a@.ru"] {
            XCTAssertFalse(RegistrationRules.looksLikeEmail(bad), bad)
        }
    }

    func testEverythingFilledMeansNothingMissing() {
        let missing = RegistrationRules.missing(email: "a@b.ru", password: "secret1", firstName: "Иван", lastName: "Петров", city: "Томск")
        XCTAssertTrue(missing.isEmpty)
        XCTAssertNil(RegistrationRules.hint(for: missing))
    }

    func testMissingFieldsAreListedInFormOrder() {
        let missing = RegistrationRules.missing(email: "", password: "123", firstName: "", lastName: "", city: "")
        XCTAssertEqual(missing, ["почта", "пароль от 6 символов", "имя", "фамилия", "город"])
    }

    func testOnlyCityMissing() {
        let missing = RegistrationRules.missing(email: "a@b.ru", password: "secret1", firstName: "Иван", lastName: "Петров", city: "  ")
        XCTAssertEqual(missing, ["город"])
        XCTAssertEqual(RegistrationRules.hint(for: missing), "Осталось заполнить: город")
    }

    func testBlankNamesCountAsMissing() {
        let missing = RegistrationRules.missing(email: "a@b.ru", password: "secret1", firstName: "   ", lastName: "\t", city: "Томск")
        XCTAssertEqual(missing, ["имя", "фамилия"])
    }

    func testPasswordBoundary() {
        XCTAssertFalse(RegistrationRules.missing(email: "a@b.ru", password: "12345", firstName: "И", lastName: "П", city: "Т").isEmpty)
        XCTAssertTrue(RegistrationRules.missing(email: "a@b.ru", password: "123456", firstName: "И", lastName: "П", city: "Т").isEmpty)
    }
}
