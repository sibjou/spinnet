import XCTest
@testable import Spinnet

final class PrivacySettingsTests: XCTestCase {

    func testDefaultsAreOpen() {
        let settings = PrivacySettings(userData: nil)
        XCTAssertTrue(settings.showStats)
        XCTAssertTrue(settings.showMatchHistory)
        XCTAssertTrue(settings.showTournaments)
        XCTAssertTrue(settings.allowClarifications)
        XCTAssertEqual(settings, PrivacySettings.default)
        XCTAssertEqual(PrivacySettings(userData: [:]), PrivacySettings.default)
    }

    func testReadsStoredValues() {
        let settings = PrivacySettings(userData: ["privacy": [
            "showStats": false, "showMatchHistory": true,
            "showTournaments": false, "allowClarifications": false
        ] as [String: Any]])
        XCTAssertFalse(settings.showStats)
        XCTAssertTrue(settings.showMatchHistory)
        XCTAssertFalse(settings.showTournaments)
        XCTAssertFalse(settings.allowClarifications)
    }

    func testMissingKeysStayOpen() {
        let settings = PrivacySettings(userData: ["privacy": ["showStats": false] as [String: Any]])
        XCTAssertFalse(settings.showStats)
        XCTAssertTrue(settings.showTournaments)
    }

    func testRoundTripThroughMap() {
        var settings = PrivacySettings()
        settings.showStats = false
        settings.allowClarifications = false
        let restored = PrivacySettings(userData: ["privacy": settings.firestoreMap as [String: Any]])
        XCTAssertEqual(restored, settings)
    }

    func testOwnerSeesEverything() {
        var settings = PrivacySettings()
        settings.showStats = false
        settings.showMatchHistory = false
        settings.showTournaments = false
        XCTAssertTrue(settings.canView(.stats, isOwner: true))
        XCTAssertTrue(settings.canView(.matchHistory, isOwner: true))
        XCTAssertTrue(settings.canView(.tournaments, isOwner: true))
    }

    func testVisitorRespectsSettings() {
        var settings = PrivacySettings()
        XCTAssertTrue(settings.canView(.stats, isOwner: false))

        settings.showStats = false
        XCTAssertFalse(settings.canView(.stats, isOwner: false))
        // история матчей — часть статистики: без неё её тоже не видно
        XCTAssertFalse(settings.canView(.matchHistory, isOwner: false))

        settings.showStats = true
        settings.showMatchHistory = false
        XCTAssertTrue(settings.canView(.stats, isOwner: false))
        XCTAssertFalse(settings.canView(.matchHistory, isOwner: false))

        settings.showTournaments = false
        XCTAssertFalse(settings.canView(.tournaments, isOwner: false))
    }
}

final class FeatureGateTests: XCTestCase {

    func testEverythingOpenWhileNoPaywall() {
        for feature in Feature.allCases {
            XCTAssertTrue(FeatureGate.isAvailable(feature, plan: .free, paywallEnabled: false))
        }
        // и значение по умолчанию сейчас выключено
        XCTAssertFalse(FeatureGate.paywallEnabled)
    }

    func testPaywallSplitsFreeAndPro() {
        XCTAssertTrue(FeatureGate.isAvailable(.statsOverview, plan: .free, paywallEnabled: true))
        XCTAssertFalse(FeatureGate.isAvailable(.statsCharts, plan: .free, paywallEnabled: true))
        XCTAssertFalse(FeatureGate.isAvailable(.statsHeatmap, plan: .free, paywallEnabled: true))
        XCTAssertFalse(FeatureGate.isAvailable(.statsHeadToHead, plan: .free, paywallEnabled: true))

        for feature in Feature.allCases {
            XCTAssertTrue(FeatureGate.isAvailable(feature, plan: .pro, paywallEnabled: true))
        }
    }

    func testPlanParsing() {
        XCTAssertEqual(Plan(raw: "pro"), .pro)
        XCTAssertEqual(Plan(raw: "free"), .free)
        XCTAssertEqual(Plan(raw: nil), .free)
        XCTAssertEqual(Plan(raw: "что-то странное"), .free)
    }
}

final class LastSeenPrivacyTests: XCTestCase {

    func testLastSeenIsVisibleByDefault() {
        XCTAssertTrue(PrivacySettings(userData: nil).showLastSeen)
        XCTAssertTrue(PrivacySettings(userData: ["privacy": ["showStats": false] as [String: Any]]).showLastSeen)
    }

    func testLastSeenCanBeHiddenAndRestored() {
        var settings = PrivacySettings()
        settings.showLastSeen = false
        let restored = PrivacySettings(userData: ["privacy": settings.firestoreMap as [String: Any]])
        XCTAssertFalse(restored.showLastSeen)
    }
}
