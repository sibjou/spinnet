import Foundation
import UserNotifications
import FirebaseFirestore
import Combine  

class NotificationService: ObservableObject {
    @Published var unreadCountValue: Int = 0
    
    private var unreadListener: ListenerRegistration?
    
    private let db = Firestore.firestore()
    static let shared = NotificationService()
    private init() {}
    
    // MARK: - Запрос разрешения
    // Вызывать при первом запуске или при первом бронировании
    func requestPermission(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound, .providesAppNotificationSettings]
        ) { granted, _ in
            DispatchQueue.main.async {
                completion?(granted)
            }
        }
    }
    
    // MARK: - Уведомление "Скоро игра" — за 3 часа до начала
    func scheduleGameReminder(
        sparringRequestId: String,
        partnerName: String,
        gameDate: Date,
        timeSlot: String
    ) {
        // Парсим время начала из "18:00 – 20:00"
        let parts = timeSlot.components(separatedBy: " – ")
        guard let startStr = parts.first else { return }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let startTime = formatter.date(from: startStr) else { return }
        
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: gameDate)
        let hour = calendar.component(.hour, from: startTime)
        let minute = calendar.component(.minute, from: startTime)
        guard let gameStart = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return }
        
        // За 3 часа до начала
        let reminderDate = gameStart.addingTimeInterval(-3 * 60 * 60)
        
        // Если время уже прошло — не планируем
        guard reminderDate > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Скоро игра 🏓"
        content.body  = "Через 3 часа игра с \(partnerName). Готовы?"
        content.sound = .default
        content.userInfo = ["type": "game_reminder", "requestId": sparringRequestId]
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "reminder_\(sparringRequestId)",
            content: content,
            trigger: trigger
        )
        print("🔔 Игра: \(gameStart), напоминание на: \(reminderDate), сейчас: \(Date())")
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Уведомление "Оцените игру" — через 2 часа после окончания
    func scheduleReviewReminder(
        sparringRequestId: String,
        partnerName: String,
        gameDate: Date,
        timeSlot: String
    ) {
        let parts = timeSlot.components(separatedBy: " – ")
        guard parts.count == 2 else { return }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let endTime = formatter.date(from: parts[1]) else { return }
        
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: gameDate)
        let hour = calendar.component(.hour, from: endTime)
        let minute = calendar.component(.minute, from: endTime)
        guard let gameEnd = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return }
        
        // Через 2 часа после окончания
        let reminderDate = gameEnd.addingTimeInterval(2 * 60 * 60)
        guard reminderDate > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Как прошла игра?"
        content.body  = "Оцените встречу с \(partnerName) — это поможет сообществу"
        content.sound = .default
        content.userInfo = ["type": "review_reminder", "requestId": sparringRequestId, "partnerName": partnerName]
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "review_\(sparringRequestId)",
            content: content,
            trigger: trigger
        )
        print("🔔 Конец игры: \(gameEnd), оценка на: \(reminderDate), сейчас: \(Date())")
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Уведомление при отмене встречи партнёром
    // Вызывается сразу при отмене — мгновенное уведомление
    func sendCancellationNotice(partnerName: String, sparringRequestId: String) {
        let content = UNMutableNotificationContent()
        content.title = "Встреча отменена"
        content.body  = "\(partnerName) отменил(а) бронирование. Оцените игрока — это повлияет на его надёжность"
        content.sound = .default
        content.userInfo = ["type": "cancellation", "requestId": sparringRequestId, "partnerName": partnerName]
        
        // Trigger nil = немедленно
        let request = UNNotificationRequest(
            identifier: "cancel_\(sparringRequestId)_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Отменить уведомления по игре (при удалении/отмене)
    func cancelGameNotifications(sparringRequestId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [
                "reminder_\(sparringRequestId)",
                "review_\(sparringRequestId)"
            ]
        )
    }
    
    // MARK: - Тестовое уведомление (удалить после проверки)
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Тест 🏓"
        content.body  = "Уведомления работают!"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "test_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Ошибка уведомления: \(error)")
            } else {
                print("✅ Уведомление запланировано на 5 секунд")
            }
        }
    }
    // MARK: - Уведомление о запросе правки отзыва
    func sendRevisionRequestNotice(reviewerName: String, reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "Требуется правка отзыва"
        content.body  = "Модератор просит изменить ваш отзыв. Причина: \(reason)"
        content.sound = .default
        content.userInfo = ["type": "revision_request"]
        
        let request = UNNotificationRequest(
            identifier: "revision_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
    // MARK: - Сохранить уведомление в Firestore
    // Уведомление сохраняется в подколлекцию notifications/{userId}/items.
    // Пользователь увидит его в Центре уведомлений при открытии приложения.
    //
    // Локальный push здесь НЕ отправляем — он бы пришёл на устройство отправителя,
    // а не получателя. Для кросс-устройственных push нужен FCM (после защиты ВКР).
    func saveAndPush(
        userId: String,
        type: NotificationType,
        title: String,
        body: String,
        targetType: String? = nil,
        targetId: String? = nil,
        sendPush: Bool = true
    ) {
        let data: [String: Any] = [
            "type":       type.rawValue,
            "title":      title,
            "body":       body,
            "targetType": targetType ?? NSNull(),
            "targetId":   targetId ?? NSNull(),
            "isRead":     false,
            "createdAt":  Timestamp()
        ]

        db.collection("notifications")
            .document(userId)
            .collection("items")
            .addDocument(data: data) { [weak self] _ in
                self?.refreshUnreadCount(userId: userId)
            }
    }
    
    // Загрузить все уведомления пользователя
    func loadNotifications(
        userId: String,
        completion: @escaping ([AppNotification]) -> Void
    ) {
        db.collection("notifications")
            .document(userId)
            .collection("items")
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments { snapshot, _ in
                let items = snapshot?.documents.compactMap {
                    AppNotification(id: $0.documentID, data: $0.data())
                } ?? []
                DispatchQueue.main.async { completion(items) }
            }
    }
    
    // Обновить опубликованное значение — вызывается из любого места приложения
    func refreshUnreadCount(userId: String) {
        unreadCount(userId: userId) { [weak self] count in
            self?.unreadCountValue = count
        }
    }
    
    // MARK: - Слушать счётчик непрочитанных в реальном времени
    // Обновляет unreadCountValue при любом изменении уведомлений,
    // независимо от того на каком экране находится пользователь.
    func startUnreadListener(userId: String) {
        unreadListener?.remove()

        unreadListener = db.collection("notifications")
            .document(userId)
            .collection("items")
            .whereField("isRead", isEqualTo: false)
            .addSnapshotListener { [weak self] snapshot, _ in
                let count = snapshot?.documents.count ?? 0
                DispatchQueue.main.async {
                    self?.unreadCountValue = count
                }
            }
    }

    func stopUnreadListener() {
        unreadListener?.remove()
        unreadListener = nil
    }
    
    // Количество непрочитанных
    func unreadCount(
        userId: String,
        completion: @escaping (Int) -> Void
    ) {
        db.collection("notifications")
            .document(userId)
            .collection("items")
            .whereField("isRead", isEqualTo: false)
            .count
            .getAggregation(source: .server) { snapshot, _ in
                let count = Int(truncating: snapshot?.count ?? 0)
                DispatchQueue.main.async { completion(count) }
            }
    }
    
    // Пометить одно уведомление как прочитанное
    func markAsRead(userId: String, notificationId: String) {
        db.collection("notifications")
            .document(userId)
            .collection("items")
            .document(notificationId)
            .updateData(["isRead": true]) { [weak self] _ in
                // Сразу пересчитываем счётчик после отметки прочитанным
                self?.refreshUnreadCount(userId: userId)
            }
    }
    
    // Пометить все как прочитанные
    func markAllAsRead(userId: String, completion: @escaping () -> Void) {
        db.collection("notifications")
            .document(userId)
            .collection("items")
            .whereField("isRead", isEqualTo: false)
            .getDocuments { [weak self] snapshot, _ in
                guard let documents = snapshot?.documents else {
                    DispatchQueue.main.async { completion() }
                    return
                }
                
                let batch = self?.db.batch()
                for doc in documents {
                    batch?.updateData(["isRead": true], forDocument: doc.reference)
                }
                batch?.commit { _ in
                    DispatchQueue.main.async {
                        // Сразу пересчитываем
                        self?.refreshUnreadCount(userId: userId)
                        completion()
                    }
                }
            }
    }
    
    // Удалить уведомление
    func deleteNotification(userId: String, notificationId: String) {
        db.collection("notifications")
            .document(userId)
            .collection("items")
            .document(notificationId)
            .delete { [weak self] _ in
                self?.refreshUnreadCount(userId: userId)
            }
    }
}
