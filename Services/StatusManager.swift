import SwiftUI
import FirebaseFirestore

// MARK: - StatusManager
// Проверяет и обновляет статусы заявок и турниров по времени
// Вызывается при запуске приложения и при открытии экранов
// Логика:
// Спарринг: active → booked (вручную) → completed (когда время прошло)
// Турнир: upcoming → in_progress (когда время наступило) → completed (вручную организатором)
class StatusManager {
    
    static let shared = StatusManager()  // Единственный экземпляр (Singleton)
    private let db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - Проверить все статусы разом
    // Вызываю при запуске приложения и при обновлении экранов
    func checkAllStatuses() {
        print("StatusManager: проверяю статусы...")
        checkSparringStatuses()
        checkTournamentStatuses()
    }
    
    // MARK: - Проверка статусов спаррингов
    // Если время встречи прошло и заявка всё ещё active — помечаю как expired
    // Если время встречи прошло и заявка booked — помечаю как completed
    private func checkSparringStatuses() {
        let now = Date()
        print("StatusManager: проверяю спарринги, текущее время: \(now)")
        
        // Проверяю активные заявки — не истекли ли
        db.collection("sparring_requests")
            .whereField("status", isEqualTo: "active")
            .getDocuments { [weak self] snapshot, _ in
                guard let documents = snapshot?.documents else { return }
                
                for doc in documents {
                    let data = doc.data()
                    if self?.isGameTimePassed(data: data, now: now) == true {
                        doc.reference.updateData(["status": "expired"])
                    }
                }
            }
        
        // Проверяю забронированные — идёт ли игра или уже завершилась
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
                        // Время полностью прошло — игра завершена
                        doc.reference.updateData([
                            "status": "completed",
                            "completedAt": Timestamp()
                        ])
                    } else if inProgress {
                        // Сейчас идёт игра
                        doc.reference.updateData(["status": "in_progress"])
                    }
                }
            }
        
        // Проверяю игры в процессе — не завершились ли
        db.collection("sparring_requests")
            .whereField("status", isEqualTo: "in_progress")
            .getDocuments { [weak self] snapshot, _ in
                guard let documents = snapshot?.documents else { return }
                
                for doc in documents {
                    let data = doc.data()
                    if self?.isGameTimePassed(data: data, now: now) == true {
                        doc.reference.updateData([
                            "status": "completed",
                            "completedAt": Timestamp()
                        ])
                    }
                }
            }
    }
    
    // MARK: - Проверка статусов турниров
    // Если время начала наступило — статус "in_progress"
    private func checkTournamentStatuses() {
        let now = Date()
        
        db.collection("tournaments")
            .whereField("status", isEqualTo: "upcoming")
            .getDocuments { [weak self] snapshot, _ in
                guard let documents = snapshot?.documents else { return }
                
                for doc in documents {
                    let data = doc.data()
                    if self?.isTournamentStarted(data: data, now: now) == true {
                        // Время начала турнира наступило
                        doc.reference.updateData(["status": "in_progress"])
                    }
                }
            }
    }
    
    // MARK: - Проверка: прошло ли время игры
    // Сравниваю дату заявки + время конца с текущим временем
    private func isGameTimePassed(data: [String: Any], now: Date) -> Bool {
        guard let dateTimestamp = data["date"] as? Timestamp,
              let timeSlot = data["timeSlot"] as? String else { return false }
        
        let gameDate = dateTimestamp.dateValue()
        
        // Извлекаю время конца из строки "18:00 – 20:00"
        let parts = timeSlot.components(separatedBy: " – ")
        guard parts.count == 2 else {
            // Если формат другой — проверяю только дату
            return Calendar.current.startOfDay(for: gameDate) < Calendar.current.startOfDay(for: now)
        }
        
        let endTimeStr = parts[1]
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        guard let endTime = formatter.date(from: endTimeStr) else {
            return Calendar.current.startOfDay(for: gameDate) < Calendar.current.startOfDay(for: now)
        }
        
        // Собираю полную дату+время конца игры
        let calendar = Calendar.current
        let gameDay = calendar.startOfDay(for: gameDate)
        let endHour = calendar.component(.hour, from: endTime)
        let endMinute = calendar.component(.minute, from: endTime)
        
        guard let fullEndDate = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: gameDay) else {
            return false
        }
        
        // Если текущее время позже конца игры — время прошло
        return now > fullEndDate
    }
    
    // MARK: - Проверка: идёт ли игра прямо сейчас
    // Текущее время между началом и концом игры
    private func isGameInProgress(data: [String: Any], now: Date) -> Bool {
        guard let dateTimestamp = data["date"] as? Timestamp,
              let timeSlot = data["timeSlot"] as? String else { return false }
        
        let gameDate = dateTimestamp.dateValue()
        let calendar = Calendar.current
        let gameDay = calendar.startOfDay(for: gameDate)
        let today = calendar.startOfDay(for: now)
        
        // Игра должна быть сегодня
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
        
        // Сейчас между началом и концом
        return now >= fullStartDate && now <= fullEndDate
    }
    
    // MARK: - Проверка: начался ли турнир
    // Сравниваю дату турнира + время начала с текущим временем
    private func isTournamentStarted(data: [String: Any], now: Date) -> Bool {
        guard let dateTimestamp = data["date"] as? Timestamp else { return false }
        
        let tournamentDate = dateTimestamp.dateValue()
        let calendar = Calendar.current
        let tournamentDay = calendar.startOfDay(for: tournamentDate)
        
        // Если есть время начала — используем его
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
        
        // Если времени нет — считаем что турнир начинается в 00:00 указанной даты
        return now >= tournamentDay
    }
}
