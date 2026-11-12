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
        
        guard let startTime = AppDate.parseClock(startStr) else { return }
        
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
        debugLog("🔔 Игра: \(gameStart), напоминание на: \(reminderDate), сейчас: \(Date())")
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Момент окончания игры
    private func gameEnd(day: Date, timeSlot: String) -> Date? {
        guard let range = GameSlot.minutes(from: timeSlot) else { return nil }
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: range.end, to: midnight)
    }

    private func calendarTrigger(at date: Date) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
    }

    // MARK: - Напоминание «Внесите счёт» — через 15 минут после окончания игры
    // Тап открывает экран счёта этой игры.
    func scheduleMatchReminder(
        sparringRequestId: String,
        partnerName: String,
        gameDate: Date,
        timeSlot: String
    ) {
        guard let end = gameEnd(day: gameDate, timeSlot: timeSlot) else { return }

        let reminderDate = end.addingTimeInterval(15 * 60)
        guard reminderDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Внесите счёт игры"
        content.body  = "Как закончилась игра с \(partnerName)? Внесите счёт — партнёр его подтвердит"
        content.sound = .default
        content.userInfo = ["type": NotificationType.matchReminder.rawValue,
                            "requestId": sparringRequestId,
                            "partnerName": partnerName]

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "match_\(sparringRequestId)",
                                  content: content,
                                  trigger: calendarTrigger(at: reminderDate))
        )
    }

    // MARK: - Напоминание «Оцените игру» — через 2 часа после окончания игры
    // Тап открывает форму отзыва. К этому времени эмоции улеглись и оценка честнее.
    func scheduleReviewReminder(
        sparringRequestId: String,
        partnerName: String,
        gameDate: Date,
        timeSlot: String
    ) {
        guard let end = gameEnd(day: gameDate, timeSlot: timeSlot) else { return }

        let reminderDate = end.addingTimeInterval(2 * 60 * 60)
        guard reminderDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Как прошла игра?"
        content.body  = "Оцените встречу с \(partnerName) — это поможет сообществу"
        content.sound = .default
        content.userInfo = ["type": NotificationType.reviewReminder.rawValue,
                            "requestId": sparringRequestId,
                            "partnerName": partnerName]

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "review_\(sparringRequestId)",
                                  content: content,
                                  trigger: calendarTrigger(at: reminderDate))
        )
    }

    // Счёт внесён — напоминание о счёте больше не нужно
    func cancelMatchReminder(sparringRequestId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["match_\(sparringRequestId)"]
        )
    }

    // Отзыв оставлен — напоминание об оценке больше не нужно
    func cancelReviewReminder(sparringRequestId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["review_\(sparringRequestId)"]
        )
    }

    // MARK: - Уведомление при отмене встречи
    // Локального уведомления нет: об отмене сообщает Firestore-уведомление
    // (см. SparringService.cancelBooking), оно приходит и на другое устройство.

    // MARK: - Отменить уведомления по игре (при удалении/отмене)
    func cancelGameNotifications(sparringRequestId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: NotificationService.gameReminderIds(for: sparringRequestId)
        )
    }

    /// Все локальные напоминания одной игры
    private static func gameReminderIds(for requestId: String) -> [String] {
        [
            "reminder_\(requestId)",
            "review_\(requestId)",
            "match_\(requestId)"
        ]
    }

    /// Убирает напоминания игр, которых больше нет в списке (отменили на другом устройстве).
    /// `activeRequestIds` — все предстоящие и идущие игры пользователя.
    func pruneGameReminders(keeping activeRequestIds: Set<String>) {
        let prefixes = ["reminder_", "review_", "match_"]
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            var stale: [String] = []
            for request in requests {
                guard let prefix = prefixes.first(where: { request.identifier.hasPrefix($0) }) else { continue }
                let requestId = String(request.identifier.dropFirst(prefix.count))
                if !activeRequestIds.contains(requestId) { stale.append(request.identifier) }
            }
            if !stale.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: stale)
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
        actorId: String? = nil,
        actorName: String? = nil,
        documentId: String? = nil,
        sendPush: Bool = true
    ) {
        var data: [String: Any] = [
            "type":       type.rawValue,
            "title":      title,
            "body":       body,
            "targetType": targetType ?? NSNull(),
            "targetId":   targetId ?? NSNull(),
            "isRead":     false,
            "createdAt":  Timestamp()
        ]
        if let actorId, !actorId.isEmpty { data["actorId"] = actorId }
        if let actorName, !actorName.isEmpty { data["actorName"] = actorName }

        let items = db.collection("notifications").document(userId).collection("items")

        if let documentId {
            // Фиксированный id: одно и то же событие не создаёт дубль,
            // даже если его зафиксируют два устройства
            items.document(documentId).setData(data) { [weak self] _ in
                self?.refreshUnreadCount(userId: userId)
            }
        } else {
            items.addDocument(data: data) { [weak self] _ in
                self?.refreshUnreadCount(userId: userId)
            }
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
        // Пока работает слушатель, число ведёт он, причём в реальном времени. Отдельный пересчёт только мешал:
        // после уведомления другому игроку он подставлял на значок число чужих непрочитанных.
        guard unreadListener == nil else { return }
        unreadCount(userId: userId) { [weak self] count in
            self?.unreadCountValue = count
        }
    }
    
    // MARK: - Слушать счётчик непрочитанных в реальном времени
    // Обновляет unreadCountValue при любом изменении уведомлений,
    // независимо от того на каком экране находится пользователь.
    func startUnreadListener(userId: String, retry: Bool = true) {
        unreadListener?.remove()

        unreadListener = db.collection("notifications")
            .document(userId)
            .collection("items")
            .whereField("isRead", isEqualTo: false)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    // Бывает при запуске, пока Firebase ещё не подтвердил вход: пробуем один раз ещё
                    debugLog("Уведомления: слушатель не запустился (\(error.localizedDescription))")
                    if retry {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self?.startUnreadListener(userId: userId, retry: false)
                        }
                    }
                    return
                }
                // Старые уведомления о переписке остались в базе: колокольчик их не считает
                let count = snapshot?.documents.filter { doc in
                    NotificationType(rawValue: doc.data()["type"] as? String ?? "")?.showsInBell ?? true
                }.count ?? 0
                DispatchQueue.main.async {
                    self?.unreadCountValue = count
                }
            }
    }

    func stopUnreadListener() {
        unreadListener?.remove()
        unreadListener = nil
        unreadCountValue = 0
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
            .whereField("type", in: NotificationType.bellRawValues)
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
