import SwiftUI
import FirebaseFirestore

class StatusManager {

    static let shared = StatusManager()
    private let db = Firestore.firestore()

    private init() {}

    func checkAllStatuses() {
        print("StatusManager: проверяю статусы...")
        checkSparringStatuses()
        checkTournamentStatuses()
    }

    // MARK: - Спарринги

    private func checkSparringStatuses() {
        let now = Date()
        print("StatusManager: проверяю спарринги, текущее время: \(now)")

        db.collection("sparring_requests")
            .whereField("status", isEqualTo: "active")
            .getDocuments { [weak self] snapshot, _ in
                guard let documents = snapshot?.documents else { return }
                for doc in documents {
                    if self?.isGameTimePassed(data: doc.data(), now: now) == true {
                        doc.reference.updateData(["status": "expired"])
                    }
                }
            }

        db.collection("sparring_requests")
            .whereField("status", isEqualTo: "booked")
            .getDocuments { [weak self] snapshot, _ in
                guard let documents = snapshot?.documents else { return }
                print("StatusManager: найдено \(documents.count) забронированных заявок")

                for doc in documents {
                    let data = doc.data()
                    let inProgress = self?.isGameInProgress(data: data, now: now) ?? false
                    let passed = self?.isGameTimePassed(data: data, now: now) ?? false
                    print("StatusManager: заявка \(doc.documentID) — inProgress: \(inProgress), passed: \(passed)")

                    if passed {
                        doc.reference.updateData([
                            "status": "completed",
                            "completedAt": Timestamp()
                        ])
                    } else if inProgress {
                        doc.reference.updateData(["status": "in_progress"])
                    }
                }
            }

        db.collection("sparring_requests")
            .whereField("status", isEqualTo: "in_progress")
            .getDocuments { [weak self] snapshot, _ in
                guard let documents = snapshot?.documents else { return }
                for doc in documents {
                    if self?.isGameTimePassed(data: doc.data(), now: now) == true {
                        doc.reference.updateData([
                            "status": "completed",
                            "completedAt": Timestamp()
                        ])
                    }
                }
            }
    }

    // MARK: - Турниры

    private func checkTournamentStatuses() {
        let now = Date()

        // upcoming → in_progress
        db.collection("tournaments")
            .whereField("status", isEqualTo: "upcoming")
            .getDocuments { [weak self] snapshot, _ in
                guard let documents = snapshot?.documents else { return }
                for doc in documents {
                    if self?.isTournamentStarted(data: doc.data(), now: now) == true {
                        doc.reference.updateData(["status": "in_progress"])
                    }
                }
            }

        // in_progress → completed
        db.collection("tournaments")
            .whereField("status", isEqualTo: "in_progress")
            .getDocuments { [weak self] snapshot, _ in
                guard let documents = snapshot?.documents else { return }
                for doc in documents {
                    if self?.isTournamentEnded(data: doc.data(), now: now) == true {
                        doc.reference.updateData([
                            "status": "completed",
                            "completedAt": Timestamp()
                        ])
                    }
                }
            }
    }

    // MARK: - Проверки времени игры

    private func isGameTimePassed(data: [String: Any], now: Date) -> Bool {
        guard let dateTimestamp = data["date"] as? Timestamp,
              let timeSlot = data["timeSlot"] as? String else { return false }

        let gameDate = dateTimestamp.dateValue()
        let parts = timeSlot.components(separatedBy: " – ")
        guard parts.count == 2 else {
            return Calendar.current.startOfDay(for: gameDate) < Calendar.current.startOfDay(for: now)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let endTime = formatter.date(from: parts[1]) else {
            return Calendar.current.startOfDay(for: gameDate) < Calendar.current.startOfDay(for: now)
        }

        let calendar = Calendar.current
        let gameDay = calendar.startOfDay(for: gameDate)
        let endHour = calendar.component(.hour, from: endTime)
        let endMinute = calendar.component(.minute, from: endTime)

        guard let fullEndDate = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: gameDay) else {
            return false
        }
        return now > fullEndDate
    }

    private func isGameInProgress(data: [String: Any], now: Date) -> Bool {
        guard let dateTimestamp = data["date"] as? Timestamp,
              let timeSlot = data["timeSlot"] as? String else { return false }

        let gameDate = dateTimestamp.dateValue()
        let calendar = Calendar.current
        let gameDay = calendar.startOfDay(for: gameDate)
        let today = calendar.startOfDay(for: now)

        guard gameDay == today else { return false }

        let parts = timeSlot.components(separatedBy: " – ")
        guard parts.count == 2 else { return false }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let startTime = formatter.date(from: parts[0]),
              let endTime = formatter.date(from: parts[1]) else { return false }

        let startHour = calendar.component(.hour, from: startTime)
        let startMinute = calendar.component(.minute, from: startTime)
        let endHour = calendar.component(.hour, from: endTime)
        let endMinute = calendar.component(.minute, from: endTime)

        guard let fullStartDate = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: gameDay),
              let fullEndDate = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: gameDay) else {
            return false
        }
        return now >= fullStartDate && now <= fullEndDate
    }

    // MARK: - Проверки времени турнира

    private func isTournamentStarted(data: [String: Any], now: Date) -> Bool {
        guard let dateTimestamp = data["date"] as? Timestamp else { return false }
        let tournamentDate = dateTimestamp.dateValue()
        let calendar = Calendar.current
        let tournamentDay = calendar.startOfDay(for: tournamentDate)

        if let startTimeStr = data["startTime"] as? String, !startTimeStr.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            if let startTime = formatter.date(from: startTimeStr) {
                let startHour = calendar.component(.hour, from: startTime)
                let startMinute = calendar.component(.minute, from: startTime)
                if let fullStartDate = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: tournamentDay) {
                    return now >= fullStartDate
                }
            }
        }
        return now >= tournamentDay
    }

    // Турнир закончился — конец последнего дня + endTime
    private func isTournamentEnded(data: [String: Any], now: Date) -> Bool {
        // Дата окончания — endDate если есть, иначе date
        let endDateValue: Date
        if let endTimestamp = data["endDate"] as? Timestamp {
            endDateValue = endTimestamp.dateValue()
        } else if let dateTimestamp = data["date"] as? Timestamp {
            endDateValue = dateTimestamp.dateValue()
        } else {
            return false
        }

        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: endDateValue)

        // Время окончания — endTime если есть, иначе 23:59
        var endHour = 23
        var endMinute = 59

        if let endTimeStr = data["endTime"] as? String, !endTimeStr.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            if let endTime = formatter.date(from: endTimeStr) {
                endHour = calendar.component(.hour, from: endTime)
                endMinute = calendar.component(.minute, from: endTime)
            }
        }

        guard let fullEndDate = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: endDay) else {
            return false
        }
        return now > fullEndDate
    }
}
