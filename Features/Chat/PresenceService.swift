import Foundation
import Combine
import FirebaseFirestore

// MARK: - PresenceService
// Отмечает, что человек сейчас в приложении: раз в минуту обновляет isOnline и lastSeenAt
// в его профиле, а при уходе в фон ставит isOnline = false.
// Если приложение закрыли принудительно и «в фон» оно не успело сообщить,
// другие всё равно увидят «не в сети» — через две с половиной минуты без обновлений
// (см. PresenceInfo.onlineTimeout).
final class PresenceService {

    static let shared = PresenceService()

    private let db = Firestore.firestore()
    private var timer: Timer?
    private var userId: String?

    private init() {}

    func goOnline(userId: String) {
        self.userId = userId
        write(userId: userId, online: true)

        timer?.invalidate()
        // Внутреннее замыкание получает собственную слабую ссылку: так Swift 6 не ругается
        // на захват изменяемой переменной из другого потока
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let id = self.userId else { return }
                self.write(userId: id, online: true)
            }
        }
    }

    /// `userId` нужен при выходе из аккаунта: запись должна уйти до того, как вход снят
    func goOffline(userId: String? = nil) {
        timer?.invalidate()
        timer = nil
        guard let id = userId ?? self.userId else { return }
        write(userId: id, online: false)
        self.userId = nil
    }

    private func write(userId: String, online: Bool) {
        db.collection("users").document(userId).updateData([
            "isOnline":   online,
            "lastSeenAt": FieldValue.serverTimestamp()
        ])
    }

    /// Присутствие из документа users/{uid}
    static func presence(from data: [String: Any]?) -> PresenceInfo {
        PresenceInfo(
            isOnline: data?["isOnline"] as? Bool ?? false,
            lastSeenAt: (data?["lastSeenAt"] as? Timestamp)?.dateValue(),
            showLastSeen: PrivacySettings(userData: data).showLastSeen
        )
    }
}

// MARK: - PartnerPresenceStore
// Следит за присутствием нескольких людей (собеседники в списке диалогов).
final class PartnerPresenceStore: ObservableObject {

    @Published private(set) var presence: [String: PresenceInfo] = [:]

    private let db = Firestore.firestore()
    private var listeners: [String: ListenerRegistration] = [:]

    deinit {
        listeners.values.forEach { $0.remove() }
    }

    func info(for userId: String) -> PresenceInfo {
        presence[userId] ?? PresenceInfo()
    }

    /// Подписывается на новых людей и отписывается от тех, кого в списке больше нет
    func watch(_ ids: Set<String>) {
        for id in Array(listeners.keys) where !ids.contains(id) {
            listeners[id]?.remove()
            listeners[id] = nil
        }
        for id in ids where !id.isEmpty && listeners[id] == nil {
            listeners[id] = db.collection("users").document(id).addSnapshotListener { [weak self] snapshot, _ in
                let info = PresenceService.presence(from: snapshot?.data())
                DispatchQueue.main.async { self?.presence[id] = info }
            }
        }
    }

    func stop() {
        listeners.values.forEach { $0.remove() }
        listeners = [:]
    }
}
