import Foundation

// MARK: - Обновление «потянуть вниз», которое не может зависнуть
// Запрос `getDocuments` без сети (или при сети без выхода в интернет) ждёт сервер около десяти секунд,
// и всё это время индикатор обновления крутится, а экран выглядит зависшим.
// Здесь ожидание ограничено: если ответа нет за `timeout`, жест завершается, а данные из памяти
// телефона остаются на экране. Запрос при этом не отменяется: когда ответ придёт, список обновится сам.

/// Срабатывает один раз: повторные вызовы возвращают false. Безопасен для вызова из любого потока.
/// Члены помечены `nonisolated`: в проекте типы по умолчанию живут на главном потоке,
/// а этот объект вызывается из ответа сервера, который приходит с другого потока.
final class OneShot: @unchecked Sendable {
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var fired = false

    nonisolated init() {}

    /// true — это первый вызов
    nonisolated func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

enum RefreshWait {

    /// Сколько секунд жест «потянуть вниз» ждёт ответа сервера
    nonisolated static let timeout: TimeInterval = 5

    /// Запускает `start`, передавая ему функцию «готово». Возвращается, когда её вызвали или вышло время.
    /// «Готово» можно вызвать несколько раз: сработает первый.
    static func wait(
        timeout: TimeInterval = RefreshWait.timeout,
        start: (@escaping @Sendable () -> Void) -> Void
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = OneShot()
            let finish: @Sendable () -> Void = {
                if once.claim() { continuation.resume() }
            }
            start(finish)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish() }
        }
    }
}
