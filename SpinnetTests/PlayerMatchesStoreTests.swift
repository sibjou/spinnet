import XCTest
@testable import Spinnet

final class PlayerMatchesStoreTests: XCTestCase {

    private func store(matches: [Match], names: [String: String] = [:], loadCount: Counter? = nil) -> PlayerMatchesStore {
        PlayerMatchesStore(
            loadMatches: { _, completion in
                loadCount?.value += 1
                completion(matches)
            },
            loadNames: { ids, completion in
                completion(names.filter { ids.contains($0.key) })
            }
        )
    }

    final class Counter { var value = 0 }

    func testLoadComputesStatsAndNames() {
        let matches = [
            makeMatch(a: "A", b: "B", games: [(11, 5), (11, 5), (11, 5)]),
            makeMatch(a: "A", b: "C", games: [(11, 5), (5, 11), (9, 11), (4, 11)], playedAt: TestCalendar.date(2026, 10, 6, 19))
        ]
        let sut = store(matches: matches, names: ["B": "Борис", "C": "Клим"])
        XCTAssertFalse(sut.hasLoaded)

        sut.load(userId: "A")

        XCTAssertTrue(sut.hasLoaded)
        XCTAssertFalse(sut.isLoading)
        XCTAssertEqual(sut.stats.matches, 2)
        XCTAssertEqual(sut.stats.wins, 1)
        XCTAssertEqual(sut.name(of: "B"), "Борис")
        XCTAssertEqual(sut.name(of: "Z"), "Игрок")
        XCTAssertEqual(sut.countedMatches.first?.playerBId, "C")        // новые сверху
    }

    func testSecondLoadIsSkippedUnlessForced() {
        let counter = Counter()
        let sut = store(matches: [], loadCount: counter)
        sut.load(userId: "A")
        sut.load(userId: "A")
        XCTAssertEqual(counter.value, 1)
        sut.load(userId: "A", force: true)
        XCTAssertEqual(counter.value, 2)
    }

    func testFindsMatchByRequestId() {
        let match = makeMatch(id: "req-1", games: [(11, 5), (11, 5), (11, 5)], status: .proposed)
        let sut = store(matches: [match])
        sut.load(userId: "A")
        XCTAssertEqual(sut.match(forRequest: "req-1")?.status, .proposed)
        XCTAssertNil(sut.match(forRequest: "other"))
        // неподтверждённые в статистику не попадают
        XCTAssertEqual(sut.stats.matches, 0)
        XCTAssertTrue(sut.countedMatches.isEmpty)
    }

    func testGroupsMatchesOfOneMeeting() {
        let matches = [
            makeMatch(id: "req-1", games: [(11, 5), (11, 5), (11, 5)]),
            makeMatch(id: "req-1_2", games: [(5, 11), (5, 11), (5, 11)]),
            makeMatch(id: "other", games: [(11, 5), (11, 5), (11, 5)])
        ]
        let sut = store(matches: matches)
        sut.load(userId: "A")
        let meeting = sut.meetingMatches(forRequest: "req-1")
        XCTAssertEqual(meeting.count, 2)
        XCTAssertEqual(meeting.matches.map { $0.ordinal }, [1, 2])
        XCTAssertEqual(sut.meetingMatches(forRequest: "nothing").count, 0)
    }

    func testIndexIsRebuiltOnReload() {
        var current = [makeMatch(id: "req-1", games: [(11, 5), (11, 5), (11, 5)])]
        let sut = PlayerMatchesStore(
            loadMatches: { _, completion in completion(current) },
            loadNames: { _, completion in completion([:]) }
        )
        sut.load(userId: "A")
        XCTAssertEqual(sut.meetingMatches(forRequest: "req-1").count, 1)
        XCTAssertEqual(sut.countedMatches.count, 1)

        current = [makeMatch(id: "req-2", games: [(11, 5), (11, 5), (11, 5)]),
                   makeMatch(id: "req-2_2", games: [(5, 11), (5, 11), (5, 11)], status: .disputed)]
        sut.load(userId: "A", force: true)

        XCTAssertEqual(sut.meetingMatches(forRequest: "req-1").count, 0)
        XCTAssertEqual(sut.meetingMatches(forRequest: "req-2").count, 2)
        XCTAssertEqual(sut.countedMatches.count, 1)       // спорный не учитывается
    }

    func testMatchesOfOneMeetingAllCountInStats() {
        let day = TestCalendar.date(2026, 10, 5, 19)
        let matches = [
            makeMatch(id: "req", games: [(11, 5), (11, 5), (11, 5)], playedAt: day),
            makeMatch(id: "req_2", games: [(5, 11), (5, 11), (5, 11)], playedAt: day),
            makeMatch(id: "req_3", games: [(11, 5), (11, 5), (11, 5)], playedAt: day)
        ]
        let sut = store(matches: matches)
        sut.load(userId: "A")
        XCTAssertEqual(sut.stats.matches, 3)
        XCTAssertEqual(sut.stats.wins, 2)
        // Внутри встречи последний внесённый — сверху
        XCTAssertEqual(sut.countedMatches.map { $0.ordinal }, [3, 2, 1])
    }
}
