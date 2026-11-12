import Foundation

// MARK: - Не ходить в сеть без нужды
// Три маленьких инструмента без привязки к Firebase и SwiftUI — поэтому их можно проверить тестами:
// «не чаще раза в N секунд», кэш с временем жизни и снимок списка блокировок для локального хранения.

// MARK: RefreshPolicy

/// Решает, пора ли обновлять данные. Нужен там, где экран может запросить загрузку несколько раз подряд
/// (переключили вкладку туда-сюда, вернулись в приложение и т. п.).
struct RefreshPolicy {
    let minInterval: TimeInterval
    private(set) var lastRun: Date?

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    /// true — можно загружать, и это запоминается. `force` пропускает проверку (после правки данных).
    mutating func shouldRun(now: Date = Date(), force: Bool = false) -> Bool {
        if !force, let lastRun, now.timeIntervalSince(lastRun) < minInterval { return false }
        lastRun = now
        return true
    }

    /// Следующая загрузка пройдёт без ожидания (например, после выхода из аккаунта)
    mutating func reset() {
        lastRun = nil
    }
}

// MARK: TimedCache

/// Словарь, в котором записи «устаревают» через `ttl` секунд
struct TimedCache<Value> {
    let ttl: TimeInterval
    private var entries: [String: (value: Value, storedAt: Date)] = [:]

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func value(for key: String, now: Date = Date()) -> Value? {
        guard let entry = entries[key], now.timeIntervalSince(entry.storedAt) < ttl else { return nil }
        return entry.value
    }

    mutating func set(_ value: Value, for key: String, now: Date = Date()) {
        entries[key] = (value, now)
    }

    mutating func remove(_ key: String) {
        entries[key] = nil
    }

    mutating func removeAll() {
        entries = [:]
    }

    /// Сколько записей хранится (в том числе устаревших, пока их не перезапишут)
    var count: Int { entries.count }
}

// MARK: BlockSnapshot

/// Список блокировок, который хранится на телефоне.
/// Лента открывается сразу с ним, а свежие данные приходят с сервера следом.
struct BlockSnapshot: Codable, Equatable {
    var blocked: [String]       // кого заблокировал я
    var blockedBy: [String]     // кто заблокировал меня

    init(blocked: Set<String>, blockedBy: Set<String>) {
        self.blocked = blocked.sorted()
        self.blockedBy = blockedBy.sorted()
    }

    var blockedSet: Set<String> { Set(blocked) }
    var blockedBySet: Set<String> { Set(blockedBy) }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    init?(data: Data) {
        guard let decoded = try? JSONDecoder().decode(BlockSnapshot.self, from: data) else { return nil }
        self = decoded
    }

    /// Ключ в UserDefaults: у каждого аккаунта на телефоне свой список
    static func storageKey(userId: String) -> String {
        "blocks.snapshot.\(userId)"
    }
}

// MARK: Имена партнёров в играх

enum PartnerNames {

    /// Дописывает `partnerName` в игры по `partnerId`. Игры без партнёра или без найденного имени не меняются.
    static func attach(_ names: [String: String], to games: [[String: Any]]) -> [[String: Any]] {
        games.map { game in
            guard let partnerId = game["partnerId"] as? String, !partnerId.isEmpty,
                  let name = names[partnerId] else { return game }
            var updated = game
            updated["partnerName"] = name
            return updated
        }
    }

    /// Какие id нужно узнать: без пустых и повторов
    static func ids(in games: [[String: Any]]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for game in games {
            guard let id = game["partnerId"] as? String, !id.isEmpty, seen.insert(id).inserted else { continue }
            result.append(id)
        }
        return result
    }

    /// Разбивает список на пачки: Firestore принимает в одном запросе `in` не больше 30 значений
    static func chunks<T>(_ items: [T], size: Int = 30) -> [[T]] {
        guard size > 0, !items.isEmpty else { return [] }
        return stride(from: 0, to: items.count, by: size).map { start in
            Array(items[start..<Swift.min(start + size, items.count)])
        }
    }
}

// MARK: - Какая это сборка
// Скорость в сборке Debug и в Release отличается в разы, а на симуляторе и телефоне тоже по-разному.
// Первая строка лога называет условия, чтобы цифры не путались.

enum BuildInfo {

    static var summary: String {
        #if DEBUG
        let configuration = "Debug"
        #else
        let configuration = "Release"
        #endif
        #if targetEnvironment(simulator)
        let device = "симулятор"
        #else
        let device = "настоящее устройство"
        #endif
        return "сборка \(configuration), \(device), iOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
}

// MARK: - Отметки времени запуска

/// Показывает в консоли Xcode, сколько прошло от запуска до каждого этапа и сколько длилась загрузка:
/// `⏱ +412 мс  лента: первый ответ` и `⏱ длится 312 мс  блокировки: мои`.
/// Печатает во всех сборках, включая Release (в консоль Xcode это видно, пока приложение запущено из Xcode).
struct PerfTimeline {
    private(set) var startedAt: Date
    private(set) var marks: [(name: String, offset: TimeInterval)] = []
    private(set) var intervals: [(name: String, duration: TimeInterval)] = []
    private var openIntervals: [String: Date] = [:]

    /// Сколько последних замеров длительности хранится (тянуть ленту можно сколько угодно раз)
    static let maxStoredIntervals = 100

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    /// Строка для консоли; повторная отметка с тем же названием не записывается
    @discardableResult
    mutating func mark(_ name: String, at date: Date = Date()) -> String? {
        guard !marks.contains(where: { $0.name == name }) else { return nil }
        let offset = max(0, date.timeIntervalSince(startedAt))
        marks.append((name, offset))
        return PerfTimeline.line(name: name, offset: offset)
    }

    /// Начало отрезка. Если такой отрезок уже начат и не закончен, отсчёт идёт заново.
    mutating func begin(_ name: String, at date: Date = Date()) {
        openIntervals[name] = date
    }

    /// Конец отрезка: строка для консоли. Без `begin` ничего не делает и возвращает nil.
    @discardableResult
    mutating func end(_ name: String, at date: Date = Date()) -> String? {
        guard let started = openIntervals.removeValue(forKey: name) else { return nil }
        let duration = max(0, date.timeIntervalSince(started))
        intervals.append((name, duration))
        if intervals.count > Self.maxStoredIntervals {
            intervals.removeFirst(intervals.count - Self.maxStoredIntervals)
        }
        return PerfTimeline.line(name: name, duration: duration)
    }

    static func line(name: String, offset: TimeInterval) -> String {
        "⏱ +\(milliseconds(offset)) мс  \(name)"
    }

    static func line(name: String, duration: TimeInterval) -> String {
        "⏱ длится \(milliseconds(duration)) мс  \(name)"
    }

    private static func milliseconds(_ interval: TimeInterval) -> Int {
        Int((interval * 1000).rounded())
    }
}

/// Вывод в консоль Xcode не на главном потоке. `print` пишет в канал отладчика и ждёт, пока тот прочитает;
/// если Xcode читает медленно, поток, который печатает, стоит. Главный поток из-за строки лога стоять не должен.
enum PerfConsole {
    nonisolated private static let queue = DispatchQueue(label: "spinnet.perf-console", qos: .utility)

    nonisolated static func write(_ line: String) {
        queue.async { print(line) }
    }
}

enum Perf {
    private static var timeline = PerfTimeline()

    /// Вызывается один раз при старте приложения
    static func start() {
        timeline = PerfTimeline()
    }

    /// Отметка «столько-то мс после запуска». Печатается один раз на название.
    static func mark(_ name: @autoclosure () -> String) {
        if let line = timeline.mark(name()) { PerfConsole.write(line) }
    }

    /// Событие, которое может повторяться (например, смена состояния приложения): печатается каждый раз
    static func event(_ name: String) {
        PerfConsole.write(PerfTimeline.line(name: name, offset: secondsSinceStart()))
    }

    /// Начало замера длительности (запрос в сеть и т. п.)
    static func begin(_ name: String) {
        timeline.begin(name)
    }

    /// Конец замера: печатает, сколько прошло с `begin`
    static func end(_ name: String) {
        if let line = timeline.end(name) { PerfConsole.write(line) }
    }

    /// Сколько секунд прошло с запуска
    static func secondsSinceStart() -> TimeInterval {
        Date().timeIntervalSince(timeline.startedAt)
    }

    private static let stallWatcher = StallWatcher()

    /// Первые `seconds` секунд следит, не завис ли экран, и печатает каждую паузу от 0,25 секунды
    static func watchMainThread(for seconds: TimeInterval = 60) {
        stallWatcher.start(for: seconds) { delay in
            if let line = StallReport.line(delay: delay, endedAt: secondsSinceStart()) { PerfConsole.write(line) }
        }
    }
}

// MARK: - Не завис ли экран
// «Ни на что не реагировало» — это значит, что главный поток был занят и не обрабатывал нажатия.
// Таймер просит сработать каждые 0,1 секунды; если главный поток занят, таймер опаздывает,
// и опоздание равно длине паузы. В консоли видно, сколько длилась пауза и когда закончилась.

enum StallReport {

    /// Паузы короче не печатаем: человек их не замечает
    static let threshold: TimeInterval = 0.25

    /// Опоздание больше этого — приложение, скорее всего, было свёрнуто (iOS замораживает таймеры), а не зависло
    static let suspendedAfter: TimeInterval = 20

    /// Строка для консоли, если пауза заметна. `endedAt` — секунды от запуска приложения
    static func line(delay: TimeInterval, endedAt: TimeInterval) -> String? {
        guard delay >= threshold, delay < suspendedAfter else { return nil }
        return "⏱ экран не отвечал \(milliseconds(delay)) мс (пауза закончилась на +\(milliseconds(endedAt)) мс)"
    }

    private static func milliseconds(_ interval: TimeInterval) -> Int {
        Int((interval * 1000).rounded())
    }
}

// MARK: - Чем занят главный поток во время паузы
// Пока экран не отвечает, отдельный поток раз в секунду смотрит на главный и сообщает, сколько процессорного времени
// тот потратил. Много — он что-то считает (строит экран, разбирает данные). Почти нет — он чего-то ждёт
// (ответа системной службы, диска, блокировки). Это разные причины, и чинятся они по-разному.

enum ProbeReport {

    /// Доля интервала, при которой главный поток считается занятым вычислениями
    static let busyShare = 0.6
    /// Доля интервала, ниже которой он считается ожидающим
    static let idleShare = 0.2

    /// Состояние потока по числу из ядра (TH_STATE_*)
    static func title(runState: Int) -> String {
        switch runState {
        case 1: return "работает"
        case 2: return "остановлен"
        case 3: return "ждёт"
        case 4: return "ждёт ответа системы или диска"
        case 5: return "остановлен"
        default: return "неизвестно"
        }
    }

    /// Вывод по доле процессорного времени за интервал
    static func verdict(cpuMilliseconds: Int, intervalMilliseconds: Int) -> String {
        guard intervalMilliseconds > 0 else { return "нет данных" }
        let share = Double(cpuMilliseconds) / Double(intervalMilliseconds)
        if share >= busyShare { return "считает" }
        if share < idleShare { return "ждёт" }
        return "считает и ждёт"
    }

    // MARK: Что ещё происходило в этот момент
    // Низкий расход процессора у главного потока можно объяснить двояко: он чего-то ждёт, или он готов работать, но
    // процессор ему не достаётся. Чтобы различить, рядом с его цифрами печатаются приоритет, загрузка процессора
    // всей системой и самые занятые потоки самого приложения.

    struct Context: Equatable {

        struct BusyThread: Equatable {
            var name: String
            var milliseconds: Int
            var priority: Int?
        }

        /// Базовый и текущий приоритеты главного потока (чем больше число, тем важнее поток)
        var mainBasePriority: Int?
        var mainCurrentPriority: Int?
        /// Какую долю времени за интервал процессоры системы простаивали, в процентах (0…100)
        var systemIdlePercent: Int?
        /// Процессорное время всех потоков приложения за интервал и их число
        var appCPUMilliseconds: Int?
        var appThreadCount: Int?
        /// Самые занятые потоки приложения, кроме главного
        var busiestThreads: [BusyThread] = []
    }

    /// Словами: насколько важен поток с таким базовым приоритетом (по классам качества обслуживания iOS)
    static func priorityTitle(_ priority: Int) -> String {
        switch priority {
        case 47...: return "интерактивный"
        case 37..<47: return "высокий"
        case 31..<37: return "обычный"
        case 20..<31: return "низкий"
        default: return "фоновый"
        }
    }

    /// Доля простоя процессоров системы в процентах по приращению счётчиков за интервал; `nil` — данных нет
    static func idlePercent(idleTicks: Int, totalTicks: Int) -> Int? {
        guard totalTicks > 0, idleTicks >= 0 else { return nil }
        return min(100, Int((Double(idleTicks) / Double(totalTicks) * 100).rounded()))
    }

    /// Поток готов работать, но почти не работает: ему не достаётся процессор. Говорит об этом только тогда,
    /// когда состояние «работает», а расходует он меньше `idleShare` интервала. `nil` — к этому случаю не относится
    static func starvation(runState: Int, cpuMilliseconds: Int, intervalMilliseconds: Int, systemIdlePercent: Int?) -> String? {
        guard runState == 1, intervalMilliseconds > 0 else { return nil }
        guard Double(cpuMilliseconds) / Double(intervalMilliseconds) < idleShare else { return nil }
        let base = "поток готов работать, но процессор ему почти не достаётся"
        guard let idle = systemIdlePercent else { return base }
        if idle >= 50 { return base + ", хотя система простаивает: похоже на ограничение, а не на нехватку мощности" }
        if idle <= 15 { return base + ": процессор занят другими потоками" }
        return base
    }

    /// Текст для консоли (время от запуска добавляет `PerfTimeline.line`). `stalledFor` — сколько экран уже
    /// не отвечает, остальное — за последний интервал
    static func text(stalledFor: TimeInterval,
                     intervalMilliseconds: Int,
                     userMilliseconds: Int,
                     systemMilliseconds: Int,
                     runState: Int,
                     context: Context? = nil) -> String {
        let cpu = userMilliseconds + systemMilliseconds
        let verdict = verdict(cpuMilliseconds: cpu, intervalMilliseconds: intervalMilliseconds)
        let stalled = Int((stalledFor * 1000).rounded())
        let main = "экран занят уже \(stalled) мс: за последние \(intervalMilliseconds) мс главный поток работал \(cpu) мс "
            + "(из них в системных вызовах \(systemMilliseconds) мс), состояние: \(title(runState: runState)) → \(verdict)"
        guard let context else { return main }

        var parts: [String] = []
        if let base = context.mainBasePriority {
            var line = "приоритет главного потока \(base) (\(priorityTitle(base)))"
            if let current = context.mainCurrentPriority, current != base { line += ", сейчас \(current)" }
            parts.append(line)
        }
        if let idle = context.systemIdlePercent {
            parts.append("процессоры системы простаивают на \(idle)%")
        }
        if let ms = context.appCPUMilliseconds, let count = context.appThreadCount {
            parts.append("всё приложение израсходовало \(ms) мс процессора, потоков \(count)")
        }
        if !context.busiestThreads.isEmpty {
            let list = context.busiestThreads.map { thread in
                let name = thread.name.isEmpty ? "поток без имени" : "«\(thread.name)»"
                let priority = thread.priority.map { " (приоритет \($0))" } ?? ""
                return "\(name) \(thread.milliseconds) мс\(priority)"
            }
            parts.append("самые занятые потоки: " + list.joined(separator: ", "))
        }
        if let note = starvation(runState: runState, cpuMilliseconds: cpu, intervalMilliseconds: intervalMilliseconds,
                                 systemIdlePercent: context.systemIdlePercent) {
            parts.append(note)
        }
        return parts.isEmpty ? main : main + "; " + parts.joined(separator: "; ")
    }
}

final class StallWatcher {

    static let tick: TimeInterval = 0.1

    private var timer: DispatchSourceTimer?
    private var expected = Date()
    private var stopAt = Date()

    /// `report` получает опоздание таймера в секундах (раз в 0,1 с, обычно около нуля)
    func start(for seconds: TimeInterval, report: @escaping (TimeInterval) -> Void) {
        timer?.cancel()
        expected = Date().addingTimeInterval(Self.tick)
        stopAt = Date().addingTimeInterval(seconds)

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + Self.tick, repeating: Self.tick, leeway: .milliseconds(10))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Date()
            report(now.timeIntervalSince(self.expected))
            self.expected = now.addingTimeInterval(Self.tick)
            if now >= self.stopAt { self.stop() }
        }
        timer = source
        source.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
