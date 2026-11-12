import XCTest
@testable import Spinnet

final class RecentVenuesTests: XCTestCase {

    func testNewVenueGoesFirst() {
        XCTAssertEqual(RecentVenues.updated(["Зал А", "Зал Б"], adding: "Зал В"), ["Зал В", "Зал А", "Зал Б"])
    }

    func testRepeatMovesToTopWithoutDuplicate() {
        XCTAssertEqual(RecentVenues.updated(["Зал А", "Зал Б", "Зал В"], adding: "зал  б"), ["зал б", "Зал А", "Зал В"])
    }

    func testListIsLimited() {
        var list: [String] = []
        for index in 1...8 { list = RecentVenues.updated(list, adding: "Зал \(index)") }
        XCTAssertEqual(list.count, RecentVenues.limit)
        XCTAssertEqual(list.first, "Зал 8")
        XCTAssertFalse(list.contains("Зал 1"))
    }

    func testEmptyVenueIsIgnored() {
        XCTAssertEqual(RecentVenues.updated(["Зал А"], adding: "   "), ["Зал А"])
        XCTAssertEqual(RecentVenues.updated([], adding: ""), [])
    }

    func testSpacesAreTidied() {
        XCTAssertEqual(RecentVenues.updated([], adding: "  Зал   ТПУ \n"), ["Зал ТПУ"])
    }

    func testYoIsTheSameAsYe() {
        XCTAssertEqual(RecentVenues.updated(["Зал Королёв"], adding: "зал королев").count, 1)
    }

    func testSuggestionsShowEverythingWhenNothingTyped() {
        XCTAssertEqual(RecentVenues.suggestions(["А", "Б"], typed: ""), ["А", "Б"])
    }

    func testSuggestionsFilterByTypedText() {
        let list = ["Зал ТПУ", "Клуб Ракетка", "Спорткомплекс Политех"]
        XCTAssertEqual(RecentVenues.suggestions(list, typed: "зал"), ["Зал ТПУ"])
        XCTAssertEqual(RecentVenues.suggestions(list, typed: "КЛУБ"), ["Клуб Ракетка"])
        XCTAssertTrue(RecentVenues.suggestions(list, typed: "стадион").isEmpty)
    }

    func testSuggestionHiddenWhenAlreadyTypedInFull() {
        XCTAssertTrue(RecentVenues.suggestions(["Зал ТПУ"], typed: "зал тпу").isEmpty)
    }

    func testStorageKeyIsPerAccount() {
        XCTAssertNotEqual(RecentVenues.storageKey(userId: "a"), RecentVenues.storageKey(userId: "b"))
    }
}
