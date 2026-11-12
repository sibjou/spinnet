import Foundation

// MARK: - Что делать, когда нет интернета
// Телефон хранит копию данных, поэтому без сети лента открывается из неё. Запись (заявку, бронь, сообщение)
// Firestore не отклоняет, а откладывает «до появления сети» и не отвечает, пока сеть не вернётся. Экран при этом
// крутит индикатор без конца. Поэтому без сети такое действие отклоняется сразу и с понятным объяснением.

enum ConnectionRule {

    /// Постоянная подсказка, пока сети нет
    static let offlineStatus = "Нет интернета · показаны сохранённые данные"

    /// Пояснение, когда действие отклонено из-за отсутствия сети
    static let actionRejected = "Нет интернета. Действие не выполнено: подключитесь к сети и повторите"

    /// Сколько секунд держится пояснение на экране
    static let noticeDuration: TimeInterval = 4

    /// Сколько секунд сеть должна пропадать, чтобы показать «Нет интернета»: при переходе между Wi-Fi и мобильной сетью
    /// связь пропадает на мгновение, и надпись мелькала бы зря
    static let offlineGrace: TimeInterval = 1
}

/// Решение перед записью, которой нужен ответ сервера
enum WriteGate {

    enum Decision: Equatable {
        case send
        case reject(message: String)
    }

    static func decide(isOnline: Bool) -> Decision {
        isOnline ? .send : .reject(message: ConnectionRule.actionRejected)
    }
}

/// Состояние связи и короткого пояснения для человека. Без системных вызовов, поэтому проверяется тестами
struct ConnectionState: Equatable {

    enum Change: Equatable {
        case none
        case wentOffline
        case cameOnline
    }

    /// До первого ответа системы считаем, что сеть есть: иначе при запуске мелькнула бы надпись «нет интернета»
    private(set) var isOnline = true
    private(set) var notice: String?
    private var noticeToken = 0

    /// Экраны, где можно показать пояснение, в порядке появления. Показывает только верхний (последний):
    /// лист поверх экрана не должен повторять пояснение, которое уже видно на нём
    private(set) var hosts: [UUID] = []
    var topHost: UUID? { hosts.last }

    mutating func register(host: UUID) {
        hosts.removeAll { $0 == host }
        hosts.append(host)
    }

    mutating func unregister(host: UUID) {
        hosts.removeAll { $0 == host }
    }

    /// Сообщает, что поменялось. Когда сеть вернулась, пояснение про отклонённое действие больше не нужно
    mutating func update(isOnline online: Bool) -> Change {
        guard online != isOnline else { return .none }
        isOnline = online
        if online {
            notice = nil
            return .cameOnline
        }
        return .wentOffline
    }

    /// Показывает пояснение. Метку нужно вернуть в `clearNotice`, когда время вышло
    mutating func show(_ text: String) -> Int {
        noticeToken += 1
        notice = text
        return noticeToken
    }

    /// Убирает пояснение, только если за это время не показали другое: новое не должно исчезнуть раньше срока
    mutating func clearNotice(token: Int) {
        if token == noticeToken { notice = nil }
    }

    func gate() -> WriteGate.Decision {
        WriteGate.decide(isOnline: isOnline)
    }
}
