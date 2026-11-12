import Foundation
import Network
import Combine
import UIKit

// MARK: - Следит за сетью
// Телефон хранит копию данных, поэтому без интернета лента открывается, но запись (бронь, заявка, сообщение)
// Firestore не отклоняет, а откладывает «до появления сети» и не отвечает: человек видит бесконечную загрузку.
// Монитор знает, есть ли сеть, и без неё отклоняет такие действия сразу, с пояснением (`ConnectionRule`).
// Правила и состояние лежат в `Connectivity.swift` и проверены тестами; здесь только связь с системой.

final class ConnectionMonitor: ObservableObject {

    static let shared = ConnectionMonitor()

    /// Есть ли сеть (после короткой задержки: см. `ConnectionRule.offlineGrace`)
    @Published private(set) var isOnline = true
    /// Пояснение для человека, пока оно на экране
    @Published private(set) var notice: String?
    /// Экран, который сейчас показывает пояснение (верхний из тех, что открыты)
    @Published private(set) var topHost: UUID?

    private var state = ConnectionState()
    private let monitor = NWPathMonitor()
    private var pendingOffline: DispatchWorkItem?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async { [weak self] in self?.pathChanged(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "spinnet.connection-monitor", qos: .utility))
    }

    // MARK: Решение перед записью

    /// Можно ли отправлять запись, которой нужен ответ сервера. Без сети показывает пояснение и возвращает `false`
    @discardableResult
    func allowWrite() -> Bool {
        switch state.gate() {
        case .send:
            return true
        case .reject(let message):
            show(message)
            return false
        }
    }

    // MARK: Экраны с пояснением

    func register(host: UUID) {
        state.register(host: host)
        publish()
    }

    func unregister(host: UUID) {
        state.unregister(host: host)
        publish()
    }

    // MARK: Изменения сети

    private func pathChanged(online: Bool) {
        pendingOffline?.cancel()
        pendingOffline = nil

        if online {
            apply(online: true)
            return
        }
        guard state.isOnline else { return }

        let work = DispatchWorkItem { [weak self] in self?.apply(online: false) }
        pendingOffline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ConnectionRule.offlineGrace, execute: work)
    }

    private func apply(online: Bool) {
        _ = state.update(isOnline: online)
        publish()
    }

    private func show(_ text: String) {
        let token = state.show(text)
        publish()
        UIAccessibility.post(notification: .announcement, argument: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + ConnectionRule.noticeDuration) { [weak self] in
            self?.state.clearNotice(token: token)
            self?.publish()
        }
    }

    private func publish() {
        isOnline = state.isOnline
        notice = state.notice
        topHost = state.topHost
    }
}

// MARK: - Отказ в нужной форме
// Записи в сервисах возвращают результат по-разному: `Bool`, идентификатор или ошибку. Без сети результат
// сообщается сразу, но не внутри вызова: вызывающий экран ждёт ответ так же, как от сервера.

extension ConnectionMonitor {

    /// Для записей с результатом `Bool`
    func allowWrite(otherwise completion: @escaping (Bool) -> Void) -> Bool {
        guard allowWrite() else {
            DispatchQueue.main.async { completion(false) }
            return false
        }
        return true
    }

    /// Для записей, где `nil` означает неудачу
    func allowWrite(otherwiseNil completion: @escaping (String?) -> Void) -> Bool {
        guard allowWrite() else {
            DispatchQueue.main.async { completion(nil) }
            return false
        }
        return true
    }

    /// Для записей с ошибкой в ответе: ошибка «нет интернета», как у системы, чтобы экран показал свой обычный текст
    func allowWrite(otherwiseFailing completion: @escaping (Error?) -> Void) -> Bool {
        guard allowWrite() else {
            let error = NSError(domain: NSURLErrorDomain, code: -1009)   // NSURLErrorNotConnectedToInternet
            DispatchQueue.main.async { completion(error) }
            return false
        }
        return true
    }
}
