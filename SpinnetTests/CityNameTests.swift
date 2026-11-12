import XCTest
@testable import Spinnet

// Один город — одно название, как бы его ни набрали. Из-за этого в фильтре истории раньше
// появлялись «Мурманск» дважды, «Санкт-Петербург» дважды и «Мурманска».

final class CityNameTests: XCTestCase {

    // MARK: Невидимые отличия

    func testCaseAndEdgeSpacesDoNotMatter() {
        for variant in ["Мурманск", "мурманск", "МУРМАНСК", "  Мурманск ", "Мурманск\u{00A0}", "Мурманск,", "Мурманск."] {
            XCTAssertEqual(CityName.canonical(variant), "Мурманск", variant.debugDescription)
        }
    }

    func testInvisibleCharactersAreIgnored() {
        XCTAssertEqual(CityName.canonical("Мур\u{200B}манск"), "Мурманск")      // нулевая ширина
        XCTAssertEqual(CityName.canonical("\u{FEFF}Мурманск"), "Мурманск")      // метка порядка байтов
    }

    func testAllKindsOfDashAndSpaceInsideName() {
        for variant in ["Санкт-Петербург", "Санкт\u{2011}Петербург", "Санкт–Петербург", "Санкт — Петербург",
                        "Санкт Петербург", "санкт-петербург", "Санкт-Петербург\u{00A0}"] {
            XCTAssertEqual(CityName.canonical(variant), "Санкт-Петербург", variant.debugDescription)
        }
    }

    func testYoAndComposedLettersAreTheSame() {
        XCTAssertEqual(CityName.key("Нижний Новгород"), CityName.key("Нижни\u{0438}\u{0306} Новгород"))   // «й» из двух знаков
        XCTAssertEqual(CityName.key("Королёв"), CityName.key("Королев"))
    }

    func testLatinLookalikesInsideRussianNameAreFixed() {
        XCTAssertEqual(CityName.canonical("\u{4D}урманск"), "Мурманск")   // «M» латинская
        XCTAssertEqual(CityName.canonical("Мурм\u{61}нск"), "Мурманск")   // «a» латинская
        XCTAssertEqual(CityName.canonical("Том\u{63}к"), "Томск")         // «c» латинская
    }

    func testPrefixTownWordIsIgnored() {
        XCTAssertEqual(CityName.canonical("г. Томск"), "Томск")
        XCTAssertEqual(CityName.canonical("г.Томск"), "Томск")
        XCTAssertEqual(CityName.canonical("город Томск"), "Томск")
    }

    // MARK: Окончания

    func testCaseEndingsMapToTheListedCity() {
        XCTAssertEqual(CityName.canonical("Мурманска"), "Мурманск")
        XCTAssertEqual(CityName.canonical("Томске"), "Томск")
        XCTAssertEqual(CityName.canonical("Омска"), "Омск")
        XCTAssertEqual(CityName.canonical("Москвы"), "Москва")
        XCTAssertEqual(CityName.canonical("Санкт-Петербурга"), "Санкт-Петербург")
        XCTAssertEqual(CityName.canonical("Новосибирске"), "Новосибирск")
    }

    func testDifferentCitiesAreNotMerged() {
        // Не отличаются «окончанием» — это другие города (или не из списка)
        XCTAssertEqual(CityName.canonical("Северск"), "Северск")
        XCTAssertEqual(CityName.canonical("Бердянск"), "Бердянск")
        XCTAssertEqual(CityName.canonical("Томск-7"), "Томск-7")
        XCTAssertNotEqual(CityName.groupKey("Томск"), CityName.groupKey("Омск"))
        XCTAssertNotEqual(CityName.groupKey("Северск"), CityName.groupKey("Североморск"))
    }

    // MARK: Неизвестные города

    func testUnknownCityIsKeptButTidied() {
        XCTAssertEqual(CityName.canonical("заполярный"), "Заполярный")
        XCTAssertEqual(CityName.canonical("  Усть   Илимск "), "Усть Илимск")
        XCTAssertEqual(CityName.canonical("усть\u{2011}илимск"), "Усть-илимск")
    }

    func testUnknownCitiesWrittenDifferentlyAreTheSame() {
        XCTAssertTrue(CityName.same("Заполярный", "заполярный "))
        XCTAssertTrue(CityName.same("Усть-Илимск", "Усть Илимск"))
        XCTAssertFalse(CityName.same("Заполярный", "Заречный"))
    }

    func testEmptyAndJunkAreEmpty() {
        XCTAssertEqual(CityName.canonical(""), "")
        XCTAssertEqual(CityName.canonical("   "), "")
        XCTAssertEqual(CityName.canonical("\u{200B}"), "")
        XCTAssertEqual(CityName.key(" , . "), "")
    }

    // MARK: Устойчивость

    func testCanonicalIsIdempotent() {
        for raw in ["Мурманска", "мурманск ", "\u{4D}урманск", "Заполярный", "усть-илимск", "г. Томск", "Томск-7"] {
            let once = CityName.canonical(raw)
            XCTAssertEqual(CityName.canonical(once), once, raw)
        }
    }

    func testEveryListedCityIsItsOwnCanonicalNameAndKeysDoNotCollide() {
        var seen: [String: String] = [:]
        for city in CityData.allCities {
            XCTAssertEqual(CityName.canonical(city), city, city)
            let key = CityName.key(city)
            XCTAssertNil(seen[key], "\(city) и \(seen[key] ?? "") получили один ключ")
            seen[key] = city
        }
    }
}
