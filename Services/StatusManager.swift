import SwiftUI
import FirebaseFirestore

// MARK: - StatusManager
// Переводит заявки и турниры между статусами по времени.
// Читает только документы, у которых дата уже наступила (status + date),
// а не все активные документы базы. Если составной индекс ещё не создан,
// запрос повторяется без фильтра по дате, поэтому статусы не «замирают».
final class StatusManager {

    static let shared = StatusManager()
    private let db = Firestore.firestore()

    /// Не чаще одного прохода в минуту: метод вызывается при запуске,
    /// возврате в приложение и открытии профиля
    private let minInterval: TimeInterval = 60
    private var lastRun: Date?

    private init() {}

    func checkAllStatuses() {
        let now = Date()
        if let lastRun, now.timeIntervalSince(lastRun) < minInterval { return }
        lastRun = now

        // Всё, что назначено на сегодня и раньше
        let startOfTomorrow = Calendar.current.date(
            byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)
        ) ?? now

        checkSparringStatuses(now: now, dateBefore: startOfTomorrow)
        checkTournamentStatuses(now: now, dateBefore: startOfTomorrow)
    }

    // MARK: - Запросы

    /// Документы с нужным статусом; при `dateBefore` — только с датой раньше указанной.
    /// Нет индекса → запасной запрос без фильтра по дате.
    private func fetch(collection: String,
                       status: String,
                       dateBefore: Date?,
                       handle: @escaping ([QueryDocumentSnapshot]) -> Void) {
        let base = db.collection(collection).whereField("status", isEqualTo: status)

        guard let dateBefore else {
            base.getDocuments { snapshot, _ in handle(snapshot?.documents ?? []) }
            return
        }

        base.whereField("date", isLessThan: Timestamp(date: dateBefore))
            .getDocuments { [weak self] snapshot, error in
                if let snapshot {
                    handle(snapshot.documents)
                    return
                }
                debugLog("StatusManager: запрос по дате не выполнен (\(error?.localizedDescription ?? "?")), читаю без фильтра")
                self?.db.collection(collection)
                    .whereField("status", isEqualTo: status)
                    .getDocuments { snapshot, _ in handle(snapshot?.documents ?? []) }
            }
    }

    // MARK: - Спарринги

    private func checkSparringStatuses(now: Date, dateBefore: Date) {
        // active → expired
        fetch(collection: "sparring_requests", status: "active", dateBefore: dateBefore) { [weak self] docs in
            for doc in docs where self?.isGameTimePassed(data: doc.data(), now: now) == true {
                doc.reference.updateData(["status": "expired"])
            }
        }

        // booked → in_progress / completed
        fetch(collection: "sparring_requests", status: "booked", dateBefore: dateBefore) { [weak self] docs in
            guard let self else { return }
            for doc in docs {
                let data = doc.data()
                if self.isGameTimePassed(data: data, now: now) {
                    doc.reference.updateData(["status": "completed", "completedAt": Timestamp()])
                } else if self.isGameInProgress(data: data, now: now) {
                    doc.reference.updateData(["status": "in_progress"])
                }
            }
        }

        // in_progress → completed (таких документов мало — фильтр по дате не нужен)
        fetch(collection: "sparring_requests", status: "in_progress", dateBefore: nil) { [weak self] docs in
            for doc in docs where self?.isGameTimePassed(data: doc.data(), now: now) == true {
                doc.reference.updateData(["status": "completed", "completedAt": Timestamp()])
            }
        }
    }

    // MARK: - Турниры

    private func checkTournamentStatuses(now: Date, dateBefore: Date) {
        // upcoming → in_progress
        fetch(collection: "tournaments", status: "upcoming", dateBefore: dateBefore) { [weak self] docs in
            for doc in docs where self?.isTournamentStarted(data: doc.data(), now: now) == true {
                doc.reference.updateData(["status": "in_progress"])
            }
        }

        // in_progress → completed
        fetch(collection: "tournaments", status: "in_progress", dateBefore: nil) { [weak self] docs in
            for doc in docs where self?.isTournamentEnded(data: doc.data(), now: now) == true {
                doc.reference.updateData(["status": "completed", "completedAt": Timestamp()])
            }
        }
    }

    // MARK: - Разбор времени

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// «HH:mm» → момент этого времени в указанный день
    private func moment(_ time: String, on day: Date) -> Date? {
        guard let parsed = Self.timeFormatter.date(from: time) else { return nil }
        let calendar = Calendar.current
        return calendar.date(
            bySettingHour: calendar.component(.hour, from: parsed),
            minute: calendar.component(.minute, from: parsed),
            second: 0,
            of: day
        )
    }

    /// Начало и конец игры, если слот записан как «HH:mm – HH:mm»
    private func gameInterval(data: [String: Any]) -> (day: Date, start: Date, end: Date)? {
        guard let timestamp = data["date"] as? Timestamp,
              let timeSlot = data["timeSlot"] as? String else { return nil }
        let day = Calendar.current.startOfDay(for: timestamp.dateValue())
        let parts = timeSlot.components(separatedBy: " – ")
        guard parts.count == 2,
              let start = moment(parts[0], on: day),
              let end = moment(parts[1], on: day) else { return nil }
        return (day, start, end)
    }

    // MARK: - Проверки времени игры

    private func isGameTimePassed(data: [String: Any], now: Date) -> Bool {
        guard let timestamp = data["date"] as? Timestamp,
              data["timeSlot"] is String else { return false }

        if let interval = gameInterval(data: data) {
            return now > interval.end
        }
        // Слот не разобрался — считаем игру прошедшей по дню
        return Calendar.current.startOfDay(for: timestamp.dateValue()) < Calendar.current.startOfDay(for: now)
    }

    private func isGameInProgress(data: [String: Any], now: Date) -> Bool {
        guard let interval = gameInterval(data: data),
              interval.day == Calendar.current.startOfDay(for: now) else { return false }
        return now >= interval.start && now <= interval.end
    }

    // MARK: - Проверки времени турнира

    private func isTournamentStarted(data: [String: Any], now: Date) -> Bool {
        guard let timestamp = data["date"] as? Timestamp else { return false }
        let day = Calendar.current.startOfDay(for: timestamp.dateValue())

        if let startTime = data["startTime"] as? String, !startTime.isEmpty,
           let start = moment(startTime, on: day) {
            return now >= start
        }
        return now >= day
    }

    // Турнир закончился — конец последнего дня + endTime (по умолчанию 23:59)
    private func isTournamentEnded(data: [String: Any], now: Date) -> Bool {
        let endValue: Date
        if let end = data["endDate"] as? Timestamp {
            endValue = end.dateValue()
        } else if let date = data["date"] as? Timestamp {
            endValue = date.dateValue()
        } else {
            return false
        }

        let day = Calendar.current.startOfDay(for: endValue)
        var endMoment = moment("23:59", on: day)
        if let endTime = data["endTime"] as? String, !endTime.isEmpty,
           let custom = moment(endTime, on: day) {
            endMoment = custom
        }
        guard let endMoment else { return false }
        return now > endMoment
    }
}
