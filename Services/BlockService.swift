import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - BlockService
// Управляет блокировками пользователей.
// Структура в Firestore: blocks/{userId}/blockedUsers/{blockedUserId}
// Блокировка работает в обе стороны: при загрузке ленты скрываем
// и тех кого я заблокировал, и тех кто заблокировал меня.
class BlockService: ObservableObject {

    static let shared = BlockService()

    private let db = Firestore.firestore()

    // Кеш: ID пользователей которых я заблокировал
    @Published var blockedUserIds: Set<String> = []
    // Кеш: ID пользователей которые заблокировали меня
    @Published var blockedByUserIds: Set<String> = []

    // Объединённый список — все с кем нет контакта (для фильтрации ленты)
    var allBlockedIds: Set<String> {
        blockedUserIds.union(blockedByUserIds)
    }

    private init() {}

    // MARK: - Свежесть данных
    // Список блокировок нужен на каждом открытии чужого профиля и при старте ленты.
    // Каждый раз спрашивать сервер (а там два запроса, один из них по всей базе) незачем:
    // блокировки меняются редко, а свои изменения мы и так вносим в кэш сразу.

    private static let freshFor: TimeInterval = 60
    private var loadedFor: String?
    private var loadedAt: Date?

    /// Список с телефона — чтобы лента открылась сразу, не дожидаясь сервера.
    /// true — сохранённый список был и подставлен.
    @discardableResult
    func restoreCache() -> Bool {
        guard let myId = Auth.auth().currentUser?.uid,
              let data = UserDefaults.standard.data(forKey: BlockSnapshot.storageKey(userId: myId)),
              let snapshot = BlockSnapshot(data: data) else { return false }
        blockedUserIds = snapshot.blockedSet
        blockedByUserIds = snapshot.blockedBySet
        return true
    }

    /// Выход из аккаунта: чужие блокировки не должны остаться в памяти
    func reset() {
        blockedUserIds = []
        blockedByUserIds = []
        loadedFor = nil
        loadedAt = nil
    }

    private func persist() {
        guard let myId = Auth.auth().currentUser?.uid else { return }
        let snapshot = BlockSnapshot(blocked: blockedUserIds, blockedBy: blockedByUserIds)
        UserDefaults.standard.set(snapshot.encoded(), forKey: BlockSnapshot.storageKey(userId: myId))
    }

    // MARK: - Загрузить мои блокировки (в обе стороны)
    /// Если список загружали меньше минуты назад — сразу вызывает `completion`, сеть не трогает.
    /// `force` — перечитать в любом случае (экран «Заблокированные»).
    func loadBlocks(force: Bool = false, completion: (() -> Void)? = nil) {
        guard let myId = Auth.auth().currentUser?.uid else {
            completion?()
            return
        }

        if !force, loadedFor == myId, let loadedAt, Date().timeIntervalSince(loadedAt) < Self.freshFor {
            completion?()
            return
        }

        let group = DispatchGroup()
        Perf.begin("блокировки: всего")
        Perf.begin("блокировки: кого заблокировал я")
        Perf.begin("блокировки: кто заблокировал меня")

        // Кого я заблокировал
        group.enter()
        db.collection("blocks").document(myId).collection("blockedUsers")
            .getDocuments { [weak self] snapshot, _ in
                let ids = snapshot?.documents.map { $0.documentID } ?? []
                DispatchQueue.main.async {
                    Perf.end("блокировки: кого заблокировал я")
                    self?.blockedUserIds = Set(ids)
                }
                group.leave()
            }

        // Кто заблокировал меня — ищем во всех блоках где есть мой id
        group.enter()
        db.collectionGroup("blockedUsers")
            .whereField("blockedUserId", isEqualTo: myId)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    debugLog("Ошибка collectionGroup (кто меня заблокировал): \(error.localizedDescription)")
                }
                let ids = snapshot?.documents.compactMap { doc -> String? in
                    doc.data()["blockedByUserId"] as? String
                } ?? []
                DispatchQueue.main.async {
                    Perf.end("блокировки: кто заблокировал меня")
                    self?.blockedByUserIds = Set(ids)
                }
                group.leave()
            }

        group.notify(queue: .main) { [weak self] in
            Perf.end("блокировки: всего")
            self?.loadedFor = myId
            self?.loadedAt = Date()
            self?.persist()
            completion?()
        }
    }

    // MARK: - Заблокировать пользователя
    func block(userId: String, completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }
        guard let myId = Auth.auth().currentUser?.uid, myId != userId else {
            completion(false)
            return
        }

        let data: [String: Any] = [
            "blockedUserId":   userId,   // кого заблокировали
            "blockedByUserId": myId,     // кто заблокировал (для обратного поиска)
            "createdAt":       Timestamp()
        ]

        db.collection("blocks").document(myId)
            .collection("blockedUsers").document(userId)
            .setData(data) { [weak self] error in
                if error == nil {
                    DispatchQueue.main.async {
                        self?.blockedUserIds.insert(userId)
                        self?.persist()
                    }
                    // Отменяем все общие забронированные игры
                    self?.cancelSharedGames(myId: myId, otherId: userId) {
                        DispatchQueue.main.async { completion(true) }
                    }
                } else {
                    DispatchQueue.main.async { completion(false) }
                }
            }
    }

    // MARK: - Разблокировать пользователя
    func unblock(userId: String, completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }
        guard let myId = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }

        db.collection("blocks").document(myId)
            .collection("blockedUsers").document(userId)
            .delete { [weak self] error in
                DispatchQueue.main.async {
                    if error == nil {
                        self?.blockedUserIds.remove(userId)
                        self?.persist()
                    }
                    completion(error == nil)
                }
            }
    }

    // MARK: - Проверка заблокирован ли пользователь (в любую сторону)
    func isBlocked(_ userId: String) -> Bool {
        allBlockedIds.contains(userId)
    }

    // MARK: - Отмена общих забронированных игр при блокировке
    // Все игры между мной и заблокированным возвращаются в ленту
    private func cancelSharedGames(myId: String, otherId: String, completion: @escaping () -> Void) {
        let group = DispatchGroup()

        // Игры где я автор, а заблокированный забронировал
        group.enter()
        db.collection("sparring_requests")
            .whereField("userId", isEqualTo: myId)
            .whereField("bookedBy", isEqualTo: otherId)
            .whereField("status", isEqualTo: "booked")
            .getDocuments { [weak self] snapshot, _ in
                self?.returnGamesToFeed(snapshot?.documents) { group.leave() }
            }

        // Игры где заблокированный автор, а я забронировал
        group.enter()
        db.collection("sparring_requests")
            .whereField("userId", isEqualTo: otherId)
            .whereField("bookedBy", isEqualTo: myId)
            .whereField("status", isEqualTo: "booked")
            .getDocuments { [weak self] snapshot, _ in
                self?.returnGamesToFeed(snapshot?.documents) { group.leave() }
            }

        group.notify(queue: .main) {
            completion()
        }
    }

    // Вспомогательная: вернуть игры в ленту (status → active, убрать bookedBy)
    private func returnGamesToFeed(_ documents: [QueryDocumentSnapshot]?, completion: @escaping () -> Void) {
        guard let documents = documents, !documents.isEmpty else {
            completion()
            return
        }

        let batch = db.batch()
        for doc in documents {
            // Отменяем запланированные напоминания по этой игре
            NotificationService.shared.cancelGameNotifications(sparringRequestId: doc.documentID)

            batch.updateData([
                "status":   "active",
                "bookedBy": FieldValue.delete(),
                "bookedAt": FieldValue.delete()
            ], forDocument: doc.reference)
        }

        batch.commit { [weak self] _ in
            // Связанные уточнения помечаем удалёнными. Отдельными запросами: диалог создаётся
            // только с первым сообщением, и если его нет, в общем пакете такая запись
            // не нашлась бы и сорвала бы возврат игры в ленту.
            for doc in documents {
                self?.db.collection("meeting_clarifications").document(doc.documentID)
                    .updateData(["status": "deleted"])
            }
            completion()
        }
    }
}
