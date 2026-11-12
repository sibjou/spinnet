import Foundation

// MARK: - Условия, в которых идёт запуск
// Перегретый телефон и режим энергосбережения снижают частоту процессора, и приложение работает медленнее.
// Это нужно знать, читая замеры, поэтому условия печатаются в первой строке лога.

enum DeviceCondition {

    static var summary: String {
        let info = ProcessInfo.processInfo
        let heat: String
        switch info.thermalState {
        case .nominal:  heat = "норма"
        case .fair:     heat = "слегка нагрет"
        case .serious:  heat = "сильно нагрет"
        case .critical: heat = "перегрет"
        @unknown default: heat = "неизвестно"
        }
        return "нагрев телефона: \(heat), энергосбережение: \(info.isLowPowerModeEnabled ? "включено" : "выключено"), "
            + "ядер процессора: \(info.activeProcessorCount) из \(info.processorCount)"
    }
}

// MARK: - Чем занят главный поток, пока экран не отвечает
// Таймер на главном потоке каждые 0,1 с отмечает «я жив». Раз в секунду отдельный поток спрашивает у ядра системы,
// сколько процессорного времени потратил главный поток и в каком он состоянии. Если отметки нет дольше полусекунды,
// результат печатается вместе с тем, что делали остальные: приоритет главного потока, загрузка процессоров всей
// системой, самые занятые потоки приложения (подробнее — в `ProbeReport`). Главный поток при этом не останавливается
// и память его не читается, поэтому проба безопасна. Следит весь сеанс (до часа): зависание бывает и не на запуске.

final class MainThreadProbe {

    static let shared = MainThreadProbe()

    /// Столько секунд без отметки — экран считается занятым
    static let busyAfter: TimeInterval = 0.5
    /// Как часто отдельный поток смотрит на главный
    static let sampleEvery: TimeInterval = 1
    /// Потоки приложения, потратившие меньше, в отчёт о самых занятых не попадают
    static let busyThreadMilliseconds = 20

    private struct ThreadReading {
        var cpuMicroseconds: Int          // пользовательское + системное время
        var systemMicroseconds: Int
        var runState: Int
        var basePriority: Int?            // nil, если система приоритет не сообщила
        var currentPriority: Int?
        var name: String
    }

    /// Счётчики процессоров всей системы: пользовательские, системные, простой, «ласковые» (nice)
    private struct SystemTicks {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    private struct Sample {
        var at: Date
        var threads: [UInt64: ThreadReading]     // по номеру потока в системе
        var system: SystemTicks?
    }

    private let queue = DispatchQueue(label: "spinnet.main-thread-probe", qos: .userInitiated)
    private let lock = NSLock()
    private var lastBeat = Date()                 // под замком: пишет главный поток, читает проба
    private var beatTimer: DispatchSourceTimer?
    private var checkTimer: DispatchSourceTimer?
    private var mainThread: mach_port_t = 0
    private var mainThreadID: UInt64?
    private var launchedAt = Date()
    private var stopAt = Date()
    private var previous: Sample?                 // только поток пробы
    private let host = mach_host_self()

    private init() {}

    /// Вызывается на главном потоке при запуске: запоминает его и следит `seconds` секунд
    func start(for seconds: TimeInterval = 3600) {
        stop()
        mainThread = pthread_mach_thread_np(pthread_self())
        var identifier = thread_identifier_info()
        mainThreadID = Self.query(mainThread, THREAD_IDENTIFIER_INFO, &identifier) ? identifier.thread_id : nil
        launchedAt = Date()
        stopAt = launchedAt.addingTimeInterval(seconds)
        previous = nil
        recordBeat()

        let beat = DispatchSource.makeTimerSource(queue: .main)
        beat.schedule(deadline: .now() + 0.1, repeating: 0.1, leeway: .milliseconds(10))
        beat.setEventHandler { [weak self] in self?.recordBeat() }
        beat.resume()
        beatTimer = beat

        let check = DispatchSource.makeTimerSource(queue: queue)
        check.schedule(deadline: .now() + Self.sampleEvery, repeating: Self.sampleEvery, leeway: .milliseconds(50))
        check.setEventHandler { [weak self] in self?.check() }
        check.resume()
        checkTimer = check
    }

    func stop() {
        beatTimer?.cancel()
        beatTimer = nil
        checkTimer?.cancel()
        checkTimer = nil
    }

    private func recordBeat() {
        lock.lock()
        lastBeat = Date()
        lock.unlock()
    }

    /// Раз в секунду в потоке пробы
    private func check() {
        let now = Date()
        if now >= stopAt {
            DispatchQueue.main.async { [weak self] in self?.stop() }
            return
        }

        lock.lock()
        let beat = lastBeat
        lock.unlock()

        let current = sample(at: now)
        let before = previous
        previous = current

        let silence = now.timeIntervalSince(beat)
        guard silence >= Self.busyAfter, let current, let before,
              let mainID = mainThreadID,
              let mainNow = current.threads[mainID], let mainBefore = before.threads[mainID] else { return }

        let interval = Int((current.at.timeIntervalSince(before.at) * 1000).rounded())
        let cpu = max(0, mainNow.cpuMicroseconds - mainBefore.cpuMicroseconds)
        let system = min(cpu, max(0, mainNow.systemMicroseconds - mainBefore.systemMicroseconds))
        let text = ProbeReport.text(
            stalledFor: silence,
            intervalMilliseconds: interval,
            userMilliseconds: (cpu - system) / 1000,
            systemMilliseconds: system / 1000,
            runState: mainNow.runState,
            context: context(current: current, before: before, mainID: mainID, mainNow: mainNow)
        )
        PerfConsole.write(PerfTimeline.line(name: text, offset: now.timeIntervalSince(launchedAt)))
    }

    /// Что делали остальные потоки и вся система за тот же интервал
    private func context(current: Sample, before: Sample, mainID: UInt64, mainNow: ThreadReading) -> ProbeReport.Context {
        var appCPU = 0
        var busy: [ProbeReport.Context.BusyThread] = []
        for (id, reading) in current.threads {
            guard let was = before.threads[id] else { continue }
            let milliseconds = max(0, reading.cpuMicroseconds - was.cpuMicroseconds) / 1000
            appCPU += milliseconds
            if id != mainID, milliseconds >= Self.busyThreadMilliseconds {
                busy.append(.init(name: reading.name, milliseconds: milliseconds, priority: reading.basePriority))
            }
        }
        busy.sort { $0.milliseconds > $1.milliseconds }

        var idlePercent: Int?
        if let after = current.system, let start = before.system {
            let user = Int(after.user &- start.user)
            let system = Int(after.system &- start.system)
            let idle = Int(after.idle &- start.idle)
            let nice = Int(after.nice &- start.nice)
            idlePercent = ProbeReport.idlePercent(idleTicks: idle, totalTicks: user + system + idle + nice)
        }

        return ProbeReport.Context(
            mainBasePriority: mainNow.basePriority,
            mainCurrentPriority: mainNow.currentPriority,
            systemIdlePercent: idlePercent,
            appCPUMilliseconds: appCPU,
            appThreadCount: current.threads.count,
            busiestThreads: Array(busy.prefix(3))
        )
    }

    // MARK: Вопросы к ядру системы

    /// Снимок всех потоков приложения и счётчиков процессоров системы
    private func sample(at date: Date) -> Sample? {
        guard mainThread != 0 else { return nil }
        var list: thread_act_array_t?
        var count = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else { return nil }
        defer {
            for index in 0..<Int(count) { mach_port_deallocate(mach_task_self_, list[index]) }
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), vm_size_t(Int(count) * MemoryLayout<thread_act_t>.size))
        }

        var threads: [UInt64: ThreadReading] = [:]
        for index in 0..<Int(count) {
            if let (id, reading) = Self.read(list[index]) { threads[id] = reading }
        }
        return Sample(at: date, threads: threads, system: systemTicks())
    }

    /// Процессорное время, состояние, приоритеты и имя одного потока
    private static func read(_ thread: mach_port_t) -> (UInt64, ThreadReading)? {
        var basic = thread_basic_info()
        var identifier = thread_identifier_info()
        guard query(thread, THREAD_BASIC_INFO, &basic), query(thread, THREAD_IDENTIFIER_INFO, &identifier) else { return nil }

        var extended = thread_extended_info()
        let hasExtended = query(thread, THREAD_EXTENDED_INFO, &extended)
        let name = hasExtended
            ? withUnsafeBytes(of: extended.pth_name) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
            : ""

        let system = Int(basic.system_time.seconds) * 1_000_000 + Int(basic.system_time.microseconds)
        let user = Int(basic.user_time.seconds) * 1_000_000 + Int(basic.user_time.microseconds)
        return (identifier.thread_id, ThreadReading(
            cpuMicroseconds: user + system,
            systemMicroseconds: system,
            runState: Int(basic.run_state),
            basePriority: hasExtended ? Int(extended.pth_priority) : nil,
            currentPriority: hasExtended ? Int(extended.pth_curpri) : nil,
            name: name
        ))
    }

    /// `thread_info` для любой структуры из `<mach/thread_info.h>`: `true`, если ядро ответило
    private static func query<Info>(_ thread: mach_port_t, _ flavor: Int32, _ info: inout Info) -> Bool {
        var count = mach_msg_type_number_t(MemoryLayout<Info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                thread_info(thread, thread_flavor_t(flavor), raw, &count)
            }
        }
        return result == KERN_SUCCESS
    }

    /// Счётчики процессоров всей системы; `nil`, если система не ответила
    private func systemTicks() -> SystemTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                host_statistics(host, HOST_CPU_LOAD_INFO, raw, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return SystemTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }
}
