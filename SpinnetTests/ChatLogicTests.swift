import XCTest
@testable import Spinnet

// MARK: - Время в переписке
final class ChatTimeTests: XCTestCase {

    private let cal = TestCalendar.utc
    private let now = TestCalendar.date(2026, 10, 13, 15, 0)

    func testClockPadsWithZeros() {
        XCTAssertEqual(ChatTime.clock(TestCalendar.date(2026, 10, 5, 9, 5), calendar: cal), "09:05")
        XCTAssertEqual(ChatTime.clock(TestCalendar.date(2026, 10, 5, 0, 0), calendar: cal), "00:00")
        XCTAssertEqual(ChatTime.clock(TestCalendar.date(2026, 10, 5, 23, 59), calendar: cal), "23:59")
    }

    func testDayMonthNames() {
        let day = TestCalendar.date(2026, 10, 12)
        XCTAssertEqual(ChatTime.dayMonth(day, calendar: cal), "12 окт")
        XCTAssertEqual(ChatTime.dayMonthFull(day, calendar: cal), "12 октября")
        XCTAssertEqual(ChatTime.dayMonthFull(TestCalendar.date(2026, 5, 1), calendar: cal), "1 мая")
        XCTAssertEqual(ChatTime.dayMonthFull(TestCalendar.date(2026, 3, 8), calendar: cal), "8 марта")
    }

    func testListStamp() {
        // Сегодня — время
        XCTAssertEqual(ChatTime.listStamp(TestCalendar.date(2026, 10, 13, 14, 5), now: now, calendar: cal), "14:05")
        // Вчера
        XCTAssertEqual(ChatTime.listStamp(TestCalendar.date(2026, 10, 12, 23, 50), now: now, calendar: cal), "вчера")
        // Раньше в этом году
        XCTAssertEqual(ChatTime.listStamp(TestCalendar.date(2026, 10, 1, 10, 0), now: now, calendar: cal), "1 окт")
        // Прошлый год
        XCTAssertEqual(ChatTime.listStamp(TestCalendar.date(2025, 12, 31, 10, 0), now: now, calendar: cal), "31.12.25")
    }

    func testDaySeparatorIsNeededOnlyWhenTheDayChanges() {
        let morning = TestCalendar.date(2026, 10, 13, 8)
        let evening = TestCalendar.date(2026, 10, 13, 22)
        let nextDay = TestCalendar.date(2026, 10, 14, 7)
        XCTAssertTrue(ChatTime.needsDaySeparator(previous: nil, current: morning, calendar: cal))
        XCTAssertFalse(ChatTime.needsDaySeparator(previous: morning, current: evening, calendar: cal))
        XCTAssertTrue(ChatTime.needsDaySeparator(previous: evening, current: nextDay, calendar: cal))
    }

    func testDaySeparator() {
        XCTAssertEqual(ChatTime.daySeparator(TestCalendar.date(2026, 10, 13, 8), now: now, calendar: cal), "Сегодня")
        XCTAssertEqual(ChatTime.daySeparator(TestCalendar.date(2026, 10, 12, 8), now: now, calendar: cal), "Вчера")
        XCTAssertEqual(ChatTime.daySeparator(TestCalendar.date(2026, 10, 1, 8), now: now, calendar: cal), "1 октября")
        XCTAssertEqual(ChatTime.daySeparator(TestCalendar.date(2025, 3, 2, 8), now: now, calendar: cal), "2 марта 2025")
    }
}

// MARK: - В сети / был(а) в сети
final class PresenceInfoTests: XCTestCase {

    private let cal = TestCalendar.utc
    private let now = TestCalendar.date(2026, 10, 13, 15, 0)

    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    func testOnlineWhenFlagSetAndHeartbeatFresh() {
        let info = PresenceInfo(isOnline: true, lastSeenAt: ago(30))
        XCTAssertTrue(info.isOnlineNow(now: now))
        XCTAssertTrue(info.showsOnlineDot(now: now))
        XCTAssertEqual(info.statusText(now: now, calendar: cal), "в сети")
    }

    func testStaleHeartbeatMeansOffline() {
        // Приложение закрыли принудительно: isOnline остался true, но вестей давно нет
        let info = PresenceInfo(isOnline: true, lastSeenAt: ago(300))
        XCTAssertFalse(info.isOnlineNow(now: now))
        XCTAssertFalse(info.showsOnlineDot(now: now))
        XCTAssertEqual(info.statusText(now: now, calendar: cal), "был(а) 5 мин назад")
    }

    func testTimeoutBoundary() {
        XCTAssertTrue(PresenceInfo(isOnline: true, lastSeenAt: ago(149)).isOnlineNow(now: now))
        XCTAssertFalse(PresenceInfo(isOnline: true, lastSeenAt: ago(150)).isOnlineNow(now: now))
    }

    func testOfflineFlagWinsOverFreshTime() {
        let info = PresenceInfo(isOnline: false, lastSeenAt: ago(20))
        XCTAssertFalse(info.isOnlineNow(now: now))
        XCTAssertEqual(info.statusText(now: now, calendar: cal), "был(а) только что")
    }

    func testMinutesAgo() {
        XCTAssertEqual(PresenceInfo(isOnline: false, lastSeenAt: ago(60)).statusText(now: now, calendar: cal), "был(а) 1 мин назад")
        XCTAssertEqual(PresenceInfo(isOnline: false, lastSeenAt: ago(3599)).statusText(now: now, calendar: cal), "был(а) 59 мин назад")
    }

    func testEarlierToday() {
        let seen = TestCalendar.date(2026, 10, 13, 13, 0)
        XCTAssertEqual(PresenceInfo(isOnline: false, lastSeenAt: seen).statusText(now: now, calendar: cal), "был(а) сегодня в 13:00")
    }

    func testYesterdayAndEarlier() {
        let yesterday = TestCalendar.date(2026, 10, 12, 21, 30)
        XCTAssertEqual(PresenceInfo(isOnline: false, lastSeenAt: yesterday).statusText(now: now, calendar: cal), "был(а) вчера в 21:30")
        let older = TestCalendar.date(2026, 10, 1, 8, 7)
        XCTAssertEqual(PresenceInfo(isOnline: false, lastSeenAt: older).statusText(now: now, calendar: cal), "был(а) 1 окт в 08:07")
    }

    func testUnknownWhenNeverSeen() {
        XCTAssertNil(PresenceInfo().statusText(now: now, calendar: cal))
        XCTAssertFalse(PresenceInfo().showsOnlineDot(now: now))
    }

    func testClockSkewIntoTheFutureStillCountsAsOnline() {
        // Часы телефона могут спешить на несколько секунд
        let info = PresenceInfo(isOnline: true, lastSeenAt: now.addingTimeInterval(10))
        XCTAssertTrue(info.isOnlineNow(now: now))
    }

    func testHiddenLastSeenShowsOnlyApproximateText() {
        let day: TimeInterval = 86_400
        XCTAssertEqual(PresenceInfo(isOnline: false, lastSeenAt: ago(2 * 3600), showLastSeen: false)
            .statusText(now: now, calendar: cal), "был(а) недавно")
        XCTAssertEqual(PresenceInfo(isOnline: false, lastSeenAt: ago(4 * day), showLastSeen: false)
            .statusText(now: now, calendar: cal), "был(а) на этой неделе")
        XCTAssertEqual(PresenceInfo(isOnline: false, lastSeenAt: ago(10 * day), showLastSeen: false)
            .statusText(now: now, calendar: cal), "был(а) в этом месяце")
        XCTAssertEqual(PresenceInfo(isOnline: false, lastSeenAt: ago(40 * day), showLastSeen: false)
            .statusText(now: now, calendar: cal), "был(а) давно")
    }

    func testHiddenLastSeenNeverRevealsOnline() {
        // Даже когда человек в сети прямо сейчас: ни точки, ни слова «в сети»
        let info = PresenceInfo(isOnline: true, lastSeenAt: ago(10), showLastSeen: false)
        XCTAssertFalse(info.showsOnlineDot(now: now))
        XCTAssertEqual(info.statusText(now: now, calendar: cal), "был(а) недавно")
    }
}

// MARK: - Предложение другого времени
final class TimeProposalTests: XCTestCase {

    private let cal = TestCalendar.utc
    private let now = TestCalendar.date(2026, 10, 13, 15, 0)
    private let currentDay = TestCalendar.date(2026, 10, 19, 0, 0)
    private let currentSlot = "19:00 – 21:00"

    private func problem(_ day: Date, _ start: Int, _ end: Int) -> TimeProposal.Problem? {
        TimeProposal(day: day, startMinutes: start, endMinutes: end)
            .problem(now: now, currentDay: currentDay, currentSlot: currentSlot, calendar: cal)
    }

    func testSlotAndSummaryFormat() {
        let proposal = TimeProposal(day: currentDay, startMinutes: 19 * 60, endMinutes: 21 * 60)
        XCTAssertEqual(proposal.slot, "19:00 – 21:00")
        XCTAssertEqual(proposal.summary(calendar: cal), "19 октября, 19:00 – 21:00")
        XCTAssertEqual(TimeProposal.clock(5 * 60 + 5), "05:05")
    }

    func testSlotParsesBackToTheSameMinutes() {
        // Хранится строкой, которую читает остальной код
        let proposal = TimeProposal(day: currentDay, startMinutes: 8 * 60 + 30, endMinutes: 10 * 60)
        let parsed = GameSlot.minutes(from: proposal.slot)
        XCTAssertEqual(parsed?.start, 8 * 60 + 30)
        XCTAssertEqual(parsed?.end, 10 * 60)
    }

    func testValidProposalHasNoProblem() {
        XCTAssertNil(problem(TestCalendar.date(2026, 10, 20, 0, 0), 18 * 60, 20 * 60))
        // Тот же день, другое время
        XCTAssertNil(problem(currentDay, 17 * 60, 19 * 60))
        // Другой день, такое же время
        XCTAssertNil(problem(TestCalendar.date(2026, 10, 20, 0, 0), 19 * 60, 21 * 60))
    }

    func testEndMustBeAfterStart() {
        XCTAssertEqual(problem(currentDay, 20 * 60, 20 * 60), .endNotAfterStart)
        XCTAssertEqual(problem(currentDay, 20 * 60, 19 * 60), .endNotAfterStart)
    }

    func testDurationLimits() {
        XCTAssertEqual(problem(currentDay, 18 * 60, 18 * 60 + 20), .tooShort)
        XCTAssertNil(problem(currentDay, 18 * 60, 18 * 60 + 30))
        XCTAssertNil(problem(currentDay, 12 * 60, 18 * 60))
        XCTAssertEqual(problem(currentDay, 12 * 60, 18 * 60 + 1), .tooLong)
    }

    func testPastTimeIsRejected() {
        let today = TestCalendar.date(2026, 10, 13, 0, 0)
        XCTAssertEqual(problem(today, 14 * 60, 16 * 60), .inPast)
        // Ровно сейчас — тоже уже прошло
        XCTAssertEqual(problem(today, 15 * 60, 17 * 60), .inPast)
        XCTAssertNil(problem(today, 15 * 60 + 1, 17 * 60))
    }

    func testSameTimeAsCurrentIsRejected() {
        XCTAssertEqual(problem(currentDay, 19 * 60, 21 * 60), .unchanged)
    }

    func testProblemMessagesAreFilled() {
        let all: [TimeProposal.Problem] = [.endNotAfterStart, .tooShort, .tooLong, .inPast, .unchanged]
        for item in all { XCTAssertFalse(item.message.isEmpty) }
        XCTAssertEqual(Set(all.map { $0.message }).count, all.count)
    }
}

// MARK: - Прочитано
final class ReadReceiptTests: XCTestCase {

    func testReadAfterPartnerOpenedTheDialog() {
        let sent = TestCalendar.date(2026, 10, 13, 12, 0)
        XCTAssertTrue(ReadReceipt.isRead(sentAt: sent, partnerReadAt: TestCalendar.date(2026, 10, 13, 12, 1)))
        XCTAssertTrue(ReadReceipt.isRead(sentAt: sent, partnerReadAt: sent))
    }

    func testUnreadWhenPartnerOpenedBeforeOrNever() {
        let sent = TestCalendar.date(2026, 10, 13, 12, 0)
        XCTAssertFalse(ReadReceipt.isRead(sentAt: sent, partnerReadAt: TestCalendar.date(2026, 10, 13, 11, 59)))
        XCTAssertFalse(ReadReceipt.isRead(sentAt: sent, partnerReadAt: nil))
    }
}

// MARK: - Разбор документов
final class MeetingDocumentsTests: XCTestCase {

    private let when = TestCalendar.date(2026, 10, 19, 19, 0)

    private func clarificationData(_ extra: [String: Any] = [:]) -> [String: Any] {
        var data: [String: Any] = [
            "sparringRequestId": "req1",
            "authorId":          "alex",
            "authorName":        "Алекс",
            "bookedById":        "ivan",
            "bookedByName":      "Иван",
            "sparringDate":      when,
            "sparringTimeSlot":  "19:00 – 21:00",
            "sparringCity":      "Томск",
            "sparringLocation":  "Клуб «Ракетка»"
        ]
        for (key, value) in extra { data[key] = value }
        return data
    }

    func testClarificationParsing() {
        let item = MeetingClarification(id: "c1", data: clarificationData())
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.sparringRequestId, "req1")
        XCTAssertEqual(item?.status, "active")
        XCTAssertFalse(item?.hasCoordinates ?? true)
        XCTAssertNil(item?.lastActionAt)
        XCTAssertEqual(item?.unreadCount(for: "alex"), 0)
    }

    func testClarificationRequiresKeyFields() {
        var data = clarificationData()
        data["bookedById"] = nil
        XCTAssertNil(MeetingClarification(id: "c1", data: data))
        data = clarificationData()
        data["sparringDate"] = "вчера"
        XCTAssertNil(MeetingClarification(id: "c1", data: data))
    }

    func testPartnerIsRelativeToCurrentUser() {
        guard let item = MeetingClarification(id: "c1", data: clarificationData()) else { return XCTFail() }
        XCTAssertEqual(item.partnerName(currentUserId: "alex"), "Иван")
        XCTAssertEqual(item.partnerId(currentUserId: "alex"), "ivan")
        XCTAssertEqual(item.partnerName(currentUserId: "ivan"), "Алекс")
        XCTAssertEqual(item.partnerId(currentUserId: "ivan"), "alex")
    }

    func testUnreadAndReadMaps() {
        let seen = TestCalendar.date(2026, 10, 13, 12, 0)
        let item = MeetingClarification(id: "c1", data: clarificationData([
            "unread": ["alex": 3, "ivan": 0] as [String: Any],
            "readAt": ["ivan": seen] as [String: Any],
            "lastActionAt": seen,
            "lastActionBy": "ivan",
            "lastActionText": "Опаздываю на 10 мин"
        ]))
        XCTAssertEqual(item?.unreadCount(for: "alex"), 3)
        XCTAssertEqual(item?.unreadCount(for: "ivan"), 0)
        XCTAssertEqual(item?.unreadCount(for: "nobody"), 0)
        XCTAssertEqual(item?.readAt["ivan"], seen)
        XCTAssertEqual(item?.activityDate, seen)
        XCTAssertEqual(item?.lastActionText, "Опаздываю на 10 мин")
    }

    func testNegativeUnreadIsClampedToZero() {
        let item = MeetingClarification(id: "c1", data: clarificationData(["unread": ["alex": -2] as [String: Any]]))
        XCTAssertEqual(item?.unreadCount(for: "alex"), 0)
    }

    func testActivityDateFallsBackToUpdatedAt() {
        let updated = TestCalendar.date(2026, 10, 10, 9, 0)
        let item = MeetingClarification(id: "c1", data: clarificationData(["updatedAt": updated]))
        XCTAssertEqual(item?.activityDate, updated)
    }

    func testCoordinatesNeedBothValues() {
        let one = MeetingClarification(id: "c1", data: clarificationData(["sparringLatitude": 56.5]))
        XCTAssertEqual(one?.hasCoordinates, false)
        let both = MeetingClarification(id: "c1", data: clarificationData(["sparringLatitude": 56.5, "sparringLongitude": 84.9]))
        XCTAssertEqual(both?.hasCoordinates, true)
    }

    func testClarificationsAreEqualById() {
        let a = MeetingClarification(id: "c1", data: clarificationData())
        let b = MeetingClarification(id: "c1", data: clarificationData(["status": "cancelled"]))
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set([a!, b!]).count, 1)
    }

    private func actionData(_ extra: [String: Any] = [:]) -> [String: Any] {
        var data: [String: Any] = [
            "clarificationId": "c1",
            "fromUserId":      "ivan",
            "fromUserName":    "Иван",
            "type":            "suggest_time",
            "proposedValue":   "20:00 – 22:00",
            "status":          "pending",
            "createdAt":       when
        ]
        for (key, value) in extra { data[key] = value }
        return data
    }

    func testActionParsing() {
        let action = MeetingAction(id: "a1", data: actionData())
        XCTAssertEqual(action?.type, .suggestTime)
        XCTAssertEqual(action?.status, .pending)
        XCTAssertEqual(action?.proposedValue, "20:00 – 22:00")
        XCTAssertFalse(action?.hasCoordinates ?? true)
        XCTAssertNil(action?.proposedDate)
        XCTAssertEqual(action?.note, "")
    }

    func testActionWithPlaceAndDate() {
        let day = TestCalendar.date(2026, 10, 21, 0, 0)
        let action = MeetingAction(id: "a1", data: actionData([
            "type": "suggest_location",
            "proposedValue": "Парк Победы",
            "latitude": 56.48, "longitude": 84.95,
            "note": "У входа",
            "proposedDate": day
        ]))
        XCTAssertEqual(action?.type, .suggestLocation)
        XCTAssertEqual(action?.hasCoordinates, true)
        XCTAssertEqual(action?.note, "У входа")
        XCTAssertEqual(action?.proposedDate, day)
    }

    func testActionRejectsUnknownTypeStatusOrMissingFields() {
        XCTAssertNil(MeetingAction(id: "a1", data: actionData(["type": "teleport"])))
        XCTAssertNil(MeetingAction(id: "a1", data: actionData(["status": "maybe"])))
        var data = actionData()
        data["createdAt"] = nil
        XCTAssertNil(MeetingAction(id: "a1", data: data))
        data = actionData()
        data["fromUserId"] = nil
        XCTAssertNil(MeetingAction(id: "a1", data: data))
    }

    func testOldActionTypesStillParse() {
        for raw in ["confirm", "suggest_time", "suggest_location", "cancel_request"] {
            XCTAssertNotNil(MeetingAction(id: "a", data: actionData(["type": raw])), raw)
        }
    }

    func testOnlyProposalsNeedAnAnswer() {
        XCTAssertTrue(MeetingActionType.confirm.needsResponse)
        XCTAssertTrue(MeetingActionType.suggestTime.needsResponse)
        XCTAssertTrue(MeetingActionType.suggestLocation.needsResponse)
        XCTAssertTrue(MeetingActionType.cancelRequest.needsResponse)
        XCTAssertFalse(MeetingActionType.message.needsResponse)
        XCTAssertFalse(MeetingActionType.late.needsResponse)
        XCTAssertFalse(MeetingActionType.arrived.needsResponse)
    }

    func testTypeLabels() {
        let message = MeetingAction(id: "a", data: actionData(["type": "message", "proposedValue": "Привет!", "status": "info"]))
        XCTAssertEqual(message?.typeLabel, "Привет!")
        let arrived = MeetingAction(id: "a", data: actionData(["type": "arrived", "status": "info"]))
        XCTAssertEqual(arrived?.typeLabel, "Я на месте")
        XCTAssertEqual(arrived?.statusLabel, "")
    }
}

// MARK: - Что отправляем
final class OutgoingActionTests: XCTestCase {

    private let cal = TestCalendar.utc

    func testStatusFollowsType() {
        XCTAssertEqual(OutgoingAction(type: .suggestTime).status, .pending)
        XCTAssertEqual(OutgoingAction(type: .cancelRequest).status, .pending)
        XCTAssertEqual(OutgoingAction(type: .message).status, .info)
        XCTAssertEqual(OutgoingAction(type: .late).status, .info)
        XCTAssertEqual(OutgoingAction(type: .arrived).status, .info)
    }

    func testPreviewTexts() {
        XCTAssertEqual(OutgoingAction(type: .confirm).previewText(calendar: cal), "Подтверждаю встречу")
        XCTAssertEqual(OutgoingAction(type: .suggestTime, value: "20:00 – 22:00").previewText(calendar: cal),
                       "Другое время: 20:00 – 22:00")
        XCTAssertEqual(OutgoingAction(type: .suggestLocation, value: "Парк Победы").previewText(calendar: cal),
                       "Место: Парк Победы")
        XCTAssertEqual(OutgoingAction(type: .cancelRequest).previewText(calendar: cal), "Предлагаю отменить встречу")
        XCTAssertEqual(OutgoingAction(type: .late, value: "15").previewText(calendar: cal), "Опаздываю на 15 мин")
        XCTAssertEqual(OutgoingAction(type: .arrived).previewText(calendar: cal), "Я на месте")
        XCTAssertEqual(OutgoingAction(type: .message, value: "  Привет  ").previewText(calendar: cal), "Привет")
    }

    func testLongMessagePreviewIsShortened() {
        let text = String(repeating: "а", count: 200)
        let preview = OutgoingAction(type: .message, value: text).previewText(calendar: cal)
        XCTAssertEqual(preview.count, 80)
        XCTAssertTrue(preview.hasSuffix("…"))
    }

    func testTimeDescriptionMentionsNewDay() {
        let day = TestCalendar.date(2026, 10, 21, 0, 0)
        let action = OutgoingAction(type: .suggestTime, value: "19:00 – 21:00", proposedDate: day)
        XCTAssertEqual(action.timeDescription(calendar: cal), "21 октября, 19:00 – 21:00")
        XCTAssertEqual(action.previewText(calendar: cal), "Другое время: 21 октября, 19:00 – 21:00")
        let sameDay = OutgoingAction(type: .suggestTime, value: "19:00 – 21:00")
        XCTAssertEqual(sameDay.timeDescription(calendar: cal), "19:00 – 21:00")
    }

    func testNotificationKinds() {
        XCTAssertEqual(OutgoingAction(type: .confirm).notificationKind, .confirm)
        XCTAssertEqual(OutgoingAction(type: .suggestTime, value: "20:00 – 22:00").notificationKind, .time("20:00 – 22:00"))
        XCTAssertEqual(OutgoingAction(type: .suggestLocation, value: "Парк").notificationKind, .place("Парк"))
        XCTAssertEqual(OutgoingAction(type: .cancelRequest).notificationKind, .cancel)
        XCTAssertEqual(OutgoingAction(type: .message, value: "Привет").notificationKind, .message("Привет"))
        XCTAssertEqual(OutgoingAction(type: .late, value: "15").notificationKind, .late(minutes: 15))
        XCTAssertEqual(OutgoingAction(type: .late, value: "abc").notificationKind, .late(minutes: 0))
        XCTAssertEqual(OutgoingAction(type: .arrived).notificationKind, .arrived)
    }
}

// MARK: - Длительность, ссылка на карты, текст времени
final class ChatHelpersTests: XCTestCase {

    func testDurationText() {
        XCTAssertEqual(TimeProposal.durationText(45), "45 мин")
        XCTAssertEqual(TimeProposal.durationText(60), "1 ч")
        XCTAssertEqual(TimeProposal.durationText(90), "1 ч 30 мин")
        XCTAssertEqual(TimeProposal.durationText(120), "2 ч")
        XCTAssertEqual(TimeProposal.durationText(0), "—")
        XCTAssertEqual(TimeProposal.durationText(-5), "—")
        let proposal = TimeProposal(day: Date(), startMinutes: 19 * 60, endMinutes: 20 * 60 + 30)
        XCTAssertEqual(proposal.durationMinutes, 90)
    }

    func testMapsLinkWithCoordinates() {
        let url = MapsLink.url(name: "Парк Победы", city: "Томск", latitude: 56.4846, longitude: 84.9482)
        let text = url?.absoluteString ?? ""
        XCTAssertTrue(text.hasPrefix("maps://?ll=56.484600,84.948200"), text)
        XCTAssertTrue(text.contains("&q="), text)
        XCTAssertFalse(text.contains(" "), text)
    }

    func testMapsLinkWithoutCoordinatesSearchesByCityAndName() {
        let text = MapsLink.url(name: "Клуб Ракетка", city: "Томск", latitude: nil, longitude: nil)?.absoluteString ?? ""
        XCTAssertTrue(text.hasPrefix("maps://?q="), text)
        XCTAssertFalse(text.contains("ll="), text)
        XCTAssertFalse(text.contains(" "), text)
    }

    func testMapsLinkEscapesSeparatorsInName() {
        let text = MapsLink.url(name: "Спорт & Co = клуб", city: "", latitude: nil, longitude: nil)?.absoluteString ?? ""
        // В значении запроса не должно остаться «&» и «=»
        let value = text.replacingOccurrences(of: "maps://?q=", with: "")
        XCTAssertFalse(value.contains("&"), text)
        XCTAssertFalse(value.contains("="), text)
    }

    func testMapsLinkNeedsSomethingToShow() {
        XCTAssertNil(MapsLink.url(name: "  ", city: "", latitude: nil, longitude: nil))
        // Только координаты — всё равно можно открыть
        XCTAssertNotNil(MapsLink.url(name: "", city: "", latitude: 56.0, longitude: 84.0))
    }

    func testActionTimeText() {
        let day = TestCalendar.date(2026, 10, 21, 0, 0)
        let withDay = MeetingAction(id: "a", data: [
            "clarificationId": "c", "fromUserId": "u", "type": "suggest_time", "status": "pending",
            "createdAt": day, "proposedValue": "19:00 – 21:00", "proposedDate": day
        ])
        XCTAssertEqual(withDay?.timeText(calendar: TestCalendar.utc), "21 октября, 19:00 – 21:00")
        let withoutDay = MeetingAction(id: "a", data: [
            "clarificationId": "c", "fromUserId": "u", "type": "suggest_time", "status": "pending",
            "createdAt": day, "proposedValue": "19:00 – 21:00"
        ])
        XCTAssertEqual(withoutDay?.timeText(calendar: TestCalendar.utc), "19:00 – 21:00")
    }
}
