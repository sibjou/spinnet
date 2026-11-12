import XCTest
@testable import Spinnet

final class RefreshPolicyTests: XCTestCase {

    private let start = TestCalendar.date(2026, 10, 13, 12, 0)

    func testFirstRunAlwaysPasses() {
        var policy = RefreshPolicy(minInterval: 60)
        XCTAssertTrue(policy.shouldRun(now: start))
    }

    func testSecondRunInsideIntervalIsSkipped() {
        var policy = RefreshPolicy(minInterval: 60)
        XCTAssertTrue(policy.shouldRun(now: start))
        XCTAssertFalse(policy.shouldRun(now: start.addingTimeInterval(59)))
    }

    func testRunPassesAfterInterval() {
        var policy = RefreshPolicy(minInterval: 60)
        XCTAssertTrue(policy.shouldRun(now: start))
        XCTAssertTrue(policy.shouldRun(now: start.addingTimeInterval(60)))
    }

    func testSkippedRunDoesNotPostponeTheNext() {
        // Пропущенный вызов не сдвигает отсчёт: через минуту от последней настоящей загрузки можно снова
        var policy = RefreshPolicy(minInterval: 60)
        XCTAssertTrue(policy.shouldRun(now: start))
        XCTAssertFalse(policy.shouldRun(now: start.addingTimeInterval(40)))
        XCTAssertTrue(policy.shouldRun(now: start.addingTimeInterval(61)))
    }

    func testForcePassesAndRestartsTheCountdown() {
        var policy = RefreshPolicy(minInterval: 60)
        XCTAssertTrue(policy.shouldRun(now: start))
        XCTAssertTrue(policy.shouldRun(now: start.addingTimeInterval(5), force: true))
        XCTAssertFalse(policy.shouldRun(now: start.addingTimeInterval(30)))
    }

    func testResetAllowsImmediateRun() {
        var policy = RefreshPolicy(minInterval: 60)
        _ = policy.shouldRun(now: start)
        policy.reset()
        XCTAssertTrue(policy.shouldRun(now: start.addingTimeInterval(1)))
    }
}

final class TimedCacheTests: XCTestCase {

    private let start = TestCalendar.date(2026, 10, 13, 12, 0)

    func testReturnsStoredValueInsideTtl() {
        var cache = TimedCache<String>(ttl: 300)
        cache.set("Анна Петрова", for: "u1", now: start)
        XCTAssertEqual(cache.value(for: "u1", now: start.addingTimeInterval(299)), "Анна Петрова")
    }

    func testValueExpiresAfterTtl() {
        var cache = TimedCache<String>(ttl: 300)
        cache.set("Анна Петрова", for: "u1", now: start)
        XCTAssertNil(cache.value(for: "u1", now: start.addingTimeInterval(300)))
    }

    func testUnknownKeyIsNil() {
        let cache = TimedCache<Int>(ttl: 10)
        XCTAssertNil(cache.value(for: "nope"))
    }

    func testSetOverwritesAndRestartsLifetime() {
        var cache = TimedCache<String>(ttl: 100)
        cache.set("старое", for: "k", now: start)
        cache.set("новое", for: "k", now: start.addingTimeInterval(90))
        XCTAssertEqual(cache.value(for: "k", now: start.addingTimeInterval(150)), "новое")
    }

    func testRemoveAndRemoveAll() {
        var cache = TimedCache<Int>(ttl: 100)
        cache.set(1, for: "a", now: start)
        cache.set(2, for: "b", now: start)
        cache.remove("a")
        XCTAssertNil(cache.value(for: "a", now: start))
        XCTAssertEqual(cache.value(for: "b", now: start), 2)
        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
    }
}

final class BlockSnapshotTests: XCTestCase {

    func testRoundTrip() {
        let snapshot = BlockSnapshot(blocked: ["u2", "u1"], blockedBy: ["u9"])
        let data = snapshot.encoded()
        XCTAssertNotNil(data)
        let restored = data.flatMap { BlockSnapshot(data: $0) }
        XCTAssertEqual(restored, snapshot)
        XCTAssertEqual(restored?.blockedSet, ["u1", "u2"])
        XCTAssertEqual(restored?.blockedBySet, ["u9"])
    }

    func testListsAreSortedSoStoredBytesDoNotJump() {
        let first = BlockSnapshot(blocked: ["b", "a", "c"], blockedBy: [])
        let second = BlockSnapshot(blocked: ["c", "b", "a"], blockedBy: [])
        XCTAssertEqual(first.blocked, ["a", "b", "c"])
        XCTAssertEqual(first, second)
    }

    func testGarbageDataGivesNil() {
        XCTAssertNil(BlockSnapshot(data: Data("не json".utf8)))
    }

    func testStorageKeyIsPerAccount() {
        XCTAssertNotEqual(BlockSnapshot.storageKey(userId: "a"), BlockSnapshot.storageKey(userId: "b"))
    }
}

final class PartnerNamesTests: XCTestCase {

    private func game(_ id: String, partner: String?) -> [String: Any] {
        var data: [String: Any] = ["documentId": id]
        if let partner { data["partnerId"] = partner }
        return data
    }

    func testIdsAreUniqueAndWithoutEmpty() {
        let games = [game("1", partner: "p1"), game("2", partner: "p2"), game("3", partner: "p1"),
                     game("4", partner: ""), game("5", partner: nil)]
        XCTAssertEqual(PartnerNames.ids(in: games), ["p1", "p2"])
    }

    func testAttachAddsNamesAndKeepsOtherGamesUntouched() {
        let games = [game("1", partner: "p1"), game("2", partner: "p2"), game("3", partner: nil)]
        let result = PartnerNames.attach(["p1": "Анна Петрова"], to: games)
        XCTAssertEqual(result[0]["partnerName"] as? String, "Анна Петрова")
        XCTAssertNil(result[1]["partnerName"])          // имени нет — поле не появляется
        XCTAssertNil(result[2]["partnerName"])
        XCTAssertEqual(result.map { $0["documentId"] as? String }, ["1", "2", "3"])
    }

    func testAttachSameNameToSeveralGames() {
        let games = (1...5).map { game("g\($0)", partner: "p1") }
        let result = PartnerNames.attach(["p1": "Борис"], to: games)
        XCTAssertTrue(result.allSatisfy { ($0["partnerName"] as? String) == "Борис" })
    }

    func testChunksRespectFirestoreLimit() {
        let ids = (1...65).map { "u\($0)" }
        let chunks = PartnerNames.chunks(ids, size: 30)
        XCTAssertEqual(chunks.map { $0.count }, [30, 30, 5])
        XCTAssertEqual(chunks.flatMap { $0 }, ids)
    }

    func testChunksOfEmptyAndSmall() {
        XCTAssertTrue(PartnerNames.chunks([String]()).isEmpty)
        XCTAssertEqual(PartnerNames.chunks(["a", "b"]).count, 1)
        XCTAssertTrue(PartnerNames.chunks(["a"], size: 0).isEmpty)
    }
}

final class PerfTimelineTests: XCTestCase {

    func testMarkReportsMillisecondsSinceStart() {
        let start = TestCalendar.date(2026, 10, 13, 12, 0)
        var timeline = PerfTimeline(startedAt: start)
        let line = timeline.mark("лента: первый ответ", at: start.addingTimeInterval(0.4123))
        XCTAssertEqual(line, "⏱ +412 мс  лента: первый ответ")
    }

    func testSameMarkIsRecordedOnce() {
        let start = TestCalendar.date(2026, 10, 13, 12, 0)
        var timeline = PerfTimeline(startedAt: start)
        XCTAssertNotNil(timeline.mark("этап", at: start.addingTimeInterval(1)))
        XCTAssertNil(timeline.mark("этап", at: start.addingTimeInterval(2)))
        XCTAssertEqual(timeline.marks.count, 1)
    }

    func testTimeBeforeStartIsClampedToZero() {
        let start = TestCalendar.date(2026, 10, 13, 12, 0)
        var timeline = PerfTimeline(startedAt: start)
        XCTAssertEqual(timeline.mark("рано", at: start.addingTimeInterval(-5)), "⏱ +0 мс  рано")
    }

    func testIntervalReportsDuration() {
        let start = TestCalendar.date(2026, 10, 13, 12, 0)
        var timeline = PerfTimeline(startedAt: start)
        timeline.begin("блокировки: мои", at: start.addingTimeInterval(1))
        let line = timeline.end("блокировки: мои", at: start.addingTimeInterval(1.3124))
        XCTAssertEqual(line, "⏱ длится 312 мс  блокировки: мои")
        XCTAssertEqual(timeline.intervals.count, 1)
        XCTAssertEqual(timeline.intervals[0].name, "блокировки: мои")
    }

    func testEndWithoutBeginDoesNothing() {
        var timeline = PerfTimeline(startedAt: TestCalendar.date(2026, 10, 13, 12, 0))
        XCTAssertNil(timeline.end("не начинали"))
        XCTAssertTrue(timeline.intervals.isEmpty)
    }

    func testIntervalCanBeRepeatedAndRestartedBeforeItEnds() {
        let start = TestCalendar.date(2026, 10, 13, 12, 0)
        var timeline = PerfTimeline(startedAt: start)
        // Второй begin до end перезапускает отсчёт: в замер не попадает время первого запроса
        timeline.begin("турниры: запрос", at: start.addingTimeInterval(1))
        timeline.begin("турниры: запрос", at: start.addingTimeInterval(5))
        XCTAssertEqual(timeline.end("турниры: запрос", at: start.addingTimeInterval(5.2)),
                       "⏱ длится 200 мс  турниры: запрос")
        // Закрытый отрезок второй раз не закрывается
        XCTAssertNil(timeline.end("турниры: запрос", at: start.addingTimeInterval(6)))
        // А новый begin/end снова работает (например, после «потянуть вниз»)
        timeline.begin("турниры: запрос", at: start.addingTimeInterval(10))
        XCTAssertEqual(timeline.end("турниры: запрос", at: start.addingTimeInterval(10.05)),
                       "⏱ длится 50 мс  турниры: запрос")
        XCTAssertEqual(timeline.intervals.count, 2)
    }

    func testIntervalsAreIndependentOfMarks() {
        let start = TestCalendar.date(2026, 10, 13, 12, 0)
        var timeline = PerfTimeline(startedAt: start)
        timeline.begin("запрос", at: start)
        timeline.mark("этап", at: start.addingTimeInterval(0.1))
        XCTAssertEqual(timeline.marks.count, 1)
        XCTAssertNotNil(timeline.end("запрос", at: start.addingTimeInterval(0.2)))
    }

    func testStoredIntervalsAreCapped() {
        let start = TestCalendar.date(2026, 10, 13, 12, 0)
        var timeline = PerfTimeline(startedAt: start)
        let total = PerfTimeline.maxStoredIntervals + 25
        for index in 0..<total {
            timeline.begin("ещё", at: start)
            timeline.end("ещё", at: start.addingTimeInterval(Double(index) / 1000))
        }
        XCTAssertEqual(timeline.intervals.count, PerfTimeline.maxStoredIntervals)
        // Остались самые свежие
        XCTAssertEqual(Int((timeline.intervals.last!.duration * 1000).rounded()), total - 1)
    }
}

// MARK: - Не завис ли экран

final class StallReportTests: XCTestCase {

    func testShortDelaysAreNotReported() {
        XCTAssertNil(StallReport.line(delay: 0, endedAt: 1))
        XCTAssertNil(StallReport.line(delay: 0.1, endedAt: 1))
        XCTAssertNil(StallReport.line(delay: StallReport.threshold - 0.001, endedAt: 1))
    }

    func testNoticeablePauseShowsLengthAndMoment() throws {
        let line = try XCTUnwrap(StallReport.line(delay: 3.04, endedAt: 5.123))
        XCTAssertTrue(line.contains("3040 мс"), line)
        XCTAssertTrue(line.contains("+5123 мс"), line)
        XCTAssertTrue(line.hasPrefix("⏱"), line)
    }

    func testPauseExactlyAtTheThresholdIsReported() {
        XCTAssertNotNil(StallReport.line(delay: StallReport.threshold, endedAt: 2))
    }

    func testTimerEarlyOrAppSuspendedIsNotAFreeze() {
        // Таймер сработал раньше срока — это не зависание
        XCTAssertNil(StallReport.line(delay: -0.5, endedAt: 2))
        // Приложение свернули: iOS заморозила таймеры, а потом они проснулись
        XCTAssertNil(StallReport.line(delay: StallReport.suspendedAfter + 1, endedAt: 90))
    }

    func testWatcherCanBeStoppedBeforeItStartsAndRestarted() {
        let watcher = StallWatcher()
        watcher.stop()
        watcher.start(for: 0.5) { _ in }
        watcher.start(for: 0.5) { _ in }
        watcher.stop()
    }
}

// MARK: - Чем занят главный поток во время паузы

final class ProbeReportTests: XCTestCase {

    func testHeavyCpuMeansTheThreadIsComputing() {
        XCTAssertEqual(ProbeReport.verdict(cpuMilliseconds: 950, intervalMilliseconds: 1000), "считает")
        XCTAssertEqual(ProbeReport.verdict(cpuMilliseconds: 600, intervalMilliseconds: 1000), "считает")
    }

    func testAlmostNoCpuMeansTheThreadIsWaiting() {
        XCTAssertEqual(ProbeReport.verdict(cpuMilliseconds: 0, intervalMilliseconds: 1000), "ждёт")
        XCTAssertEqual(ProbeReport.verdict(cpuMilliseconds: 199, intervalMilliseconds: 1000), "ждёт")
    }

    func testInBetweenIsMixed() {
        XCTAssertEqual(ProbeReport.verdict(cpuMilliseconds: 200, intervalMilliseconds: 1000), "считает и ждёт")
        XCTAssertEqual(ProbeReport.verdict(cpuMilliseconds: 599, intervalMilliseconds: 1000), "считает и ждёт")
    }

    func testEmptyIntervalIsNotDividedBy() {
        XCTAssertEqual(ProbeReport.verdict(cpuMilliseconds: 10, intervalMilliseconds: 0), "нет данных")
        XCTAssertEqual(ProbeReport.verdict(cpuMilliseconds: 10, intervalMilliseconds: -5), "нет данных")
    }

    func testRunStatesHaveNames() {
        XCTAssertEqual(ProbeReport.title(runState: 1), "работает")
        XCTAssertEqual(ProbeReport.title(runState: 3), "ждёт")
        XCTAssertEqual(ProbeReport.title(runState: 4), "ждёт ответа системы или диска")
        XCTAssertEqual(ProbeReport.title(runState: 0), "неизвестно")
        XCTAssertEqual(ProbeReport.title(runState: 99), "неизвестно")
    }

    func testTextShowsEveryNumber() {
        let line = ProbeReport.text(stalledFor: 3.04, intervalMilliseconds: 1000,
                                    userMilliseconds: 900, systemMilliseconds: 40, runState: 1)
        XCTAssertTrue(line.hasPrefix("экран занят"), line)
        XCTAssertTrue(line.contains("3040 мс"), line)
        XCTAssertTrue(line.contains("940 мс"), line)
        XCTAssertTrue(line.contains("40 мс"), line)
        XCTAssertTrue(line.contains("работает"), line)
        XCTAssertTrue(line.contains("считает"), line)
    }

    func testWaitingThreadIsCalledWaiting() {
        let line = ProbeReport.text(stalledFor: 5, intervalMilliseconds: 1000,
                                    userMilliseconds: 3, systemMilliseconds: 1, runState: 3)
        XCTAssertTrue(line.contains("ждёт"), line)
        XCTAssertFalse(line.contains("считает"), line)
    }

    // MARK: Приоритеты, простой системы, нехватка процессора

    func testPrioritiesHaveNames() {
        XCTAssertEqual(ProbeReport.priorityTitle(47), "интерактивный")
        XCTAssertEqual(ProbeReport.priorityTitle(46), "высокий")
        XCTAssertEqual(ProbeReport.priorityTitle(37), "высокий")
        XCTAssertEqual(ProbeReport.priorityTitle(31), "обычный")
        XCTAssertEqual(ProbeReport.priorityTitle(20), "низкий")
        XCTAssertEqual(ProbeReport.priorityTitle(19), "фоновый")
        XCTAssertEqual(ProbeReport.priorityTitle(4), "фоновый")
    }

    func testIdlePercentFromTicks() {
        XCTAssertEqual(ProbeReport.idlePercent(idleTicks: 50, totalTicks: 100), 50)
        XCTAssertEqual(ProbeReport.idlePercent(idleTicks: 0, totalTicks: 100), 0)
        XCTAssertEqual(ProbeReport.idlePercent(idleTicks: 100, totalTicks: 100), 100)
        XCTAssertEqual(ProbeReport.idlePercent(idleTicks: 2, totalTicks: 3), 67)
    }

    func testIdlePercentWithoutDataIsNil() {
        XCTAssertNil(ProbeReport.idlePercent(idleTicks: 5, totalTicks: 0))
        XCTAssertNil(ProbeReport.idlePercent(idleTicks: -1, totalTicks: 100))
    }

    func testIdlePercentNeverExceedsHundred() {
        XCTAssertEqual(ProbeReport.idlePercent(idleTicks: 150, totalTicks: 100), 100)
    }

    func testRunnableThreadWithoutCpuOnIdleSystemIsThrottled() throws {
        let note = try XCTUnwrap(ProbeReport.starvation(runState: 1, cpuMilliseconds: 120, intervalMilliseconds: 1000,
                                                        systemIdlePercent: 70))
        XCTAssertTrue(note.contains("ограничение"), note)
    }

    func testRunnableThreadWithoutCpuOnBusySystemIsStarvedByOthers() throws {
        let note = try XCTUnwrap(ProbeReport.starvation(runState: 1, cpuMilliseconds: 120, intervalMilliseconds: 1000,
                                                        systemIdlePercent: 5))
        XCTAssertTrue(note.contains("занят другими"), note)
    }

    func testRunnableThreadWithoutCpuAndUnknownLoadIsStillReported() throws {
        let unknown = try XCTUnwrap(ProbeReport.starvation(runState: 1, cpuMilliseconds: 120, intervalMilliseconds: 1000,
                                                           systemIdlePercent: nil))
        XCTAssertFalse(unknown.contains("ограничение"), unknown)
        XCTAssertFalse(unknown.contains("занят другими"), unknown)
        let middle = try XCTUnwrap(ProbeReport.starvation(runState: 1, cpuMilliseconds: 120, intervalMilliseconds: 1000,
                                                          systemIdlePercent: 30))
        XCTAssertFalse(middle.contains("ограничение"), middle)
        XCTAssertFalse(middle.contains("занят другими"), middle)
    }

    func testStarvationIsOnlyAboutRunnableThreadsWithLittleCpu() {
        // ждёт — это не нехватка процессора
        XCTAssertNil(ProbeReport.starvation(runState: 3, cpuMilliseconds: 10, intervalMilliseconds: 1000, systemIdlePercent: 70))
        // работает и действительно считает
        XCTAssertNil(ProbeReport.starvation(runState: 1, cpuMilliseconds: 900, intervalMilliseconds: 1000, systemIdlePercent: 70))
        // граница: ровно idleShare — уже не «почти не достаётся»
        XCTAssertNil(ProbeReport.starvation(runState: 1, cpuMilliseconds: 200, intervalMilliseconds: 1000, systemIdlePercent: 70))
        XCTAssertNil(ProbeReport.starvation(runState: 1, cpuMilliseconds: 0, intervalMilliseconds: 0, systemIdlePercent: 70))
    }

    // MARK: Текст с контекстом

    private func context() -> ProbeReport.Context {
        ProbeReport.Context(
            mainBasePriority: 47,
            mainCurrentPriority: 47,
            systemIdlePercent: 62,
            appCPUMilliseconds: 340,
            appThreadCount: 28,
            busiestThreads: [
                .init(name: "com.google.firebase.firestore", milliseconds: 120, priority: 31),
                .init(name: "", milliseconds: 80, priority: nil)
            ]
        )
    }

    func testContextIsAppendedAfterTheMainNumbers() {
        let plain = ProbeReport.text(stalledFor: 5, intervalMilliseconds: 1000,
                                     userMilliseconds: 100, systemMilliseconds: 10, runState: 1)
        let line = ProbeReport.text(stalledFor: 5, intervalMilliseconds: 1000,
                                    userMilliseconds: 100, systemMilliseconds: 10, runState: 1, context: context())
        XCTAssertTrue(line.hasPrefix(plain), line)
        XCTAssertTrue(line.contains("приоритет главного потока 47 (интерактивный)"), line)
        XCTAssertTrue(line.contains("простаивают на 62%"), line)
        XCTAssertTrue(line.contains("340 мс процессора, потоков 28"), line)
        XCTAssertTrue(line.contains("«com.google.firebase.firestore» 120 мс (приоритет 31)"), line)
        XCTAssertTrue(line.contains("поток без имени 80 мс"), line)
        XCTAssertTrue(line.contains("ограничение"), line)
    }

    func testCurrentPriorityIsShownOnlyWhenItDiffersFromBase() {
        var changed = context()
        changed.mainCurrentPriority = 4
        let line = ProbeReport.text(stalledFor: 5, intervalMilliseconds: 1000,
                                    userMilliseconds: 100, systemMilliseconds: 10, runState: 1, context: changed)
        XCTAssertTrue(line.contains("сейчас 4"), line)
        let same = ProbeReport.text(stalledFor: 5, intervalMilliseconds: 1000,
                                    userMilliseconds: 100, systemMilliseconds: 10, runState: 1, context: context())
        XCTAssertFalse(same.contains("сейчас"), same)
    }

    func testEmptyContextAddsNothing() {
        let plain = ProbeReport.text(stalledFor: 5, intervalMilliseconds: 1000,
                                     userMilliseconds: 100, systemMilliseconds: 10, runState: 3)
        let line = ProbeReport.text(stalledFor: 5, intervalMilliseconds: 1000,
                                    userMilliseconds: 100, systemMilliseconds: 10, runState: 3,
                                    context: ProbeReport.Context())
        XCTAssertEqual(line, plain)
    }

    func testWaitingThreadGetsNoStarvationNote() {
        let line = ProbeReport.text(stalledFor: 5, intervalMilliseconds: 1000,
                                    userMilliseconds: 3, systemMilliseconds: 1, runState: 3, context: context())
        XCTAssertFalse(line.contains("готов работать"), line)
        XCTAssertTrue(line.contains("приоритет главного потока"), line)
    }
}

// MARK: - Какая это сборка

final class BuildInfoTests: XCTestCase {

    func testSummaryNamesBuildAndDevice() {
        let text = BuildInfo.summary
        XCTAssertTrue(text.contains("Debug") || text.contains("Release"), text)
        XCTAssertTrue(text.contains("симулятор") || text.contains("настоящее устройство"), text)
        XCTAssertTrue(text.contains("iOS") || text.contains("Version"), text)
    }
}
