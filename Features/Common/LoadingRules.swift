import Foundation

// MARK: - Когда лента считается загруженной
// Телефон хранит копию данных и отвечает на запрос сразу, не дожидаясь сервера. Но на первом запуске
// и после переустановки копия пустая, и пустой ответ из неё не значит «заявок нет». Раньше такой ответ
// сразу показывался как «Пока нет заявок», и это держалось, пока не отвечал сервер (6–11 секунд на медленной сети).
// Теперь пустой ответ из копии телефона игнорируется, пока идёт загрузка: человек видит анимацию.

enum FeedLoadRule {

    /// Сколько секунд ждать сервер после пустого ответа из копии телефона. Без сети сервер не ответит вовсе,
    /// а бесконечная загрузка хуже пустой ленты: по истечении времени показываем то, что есть
    static let giveUpAfter: TimeInterval = 10

    /// Ответ можно показывать как первый результат?
    /// - `fromCache`: ответ из копии на телефоне (`nil` — источник неизвестен)
    /// - `isEmpty`: заявок в ответе нет
    /// - `hasError`: запрос закончился ошибкой (ждать больше нечего)
    static func countsAsLoaded(fromCache: Bool?, isEmpty: Bool, hasError: Bool) -> Bool {
        if hasError { return true }
        guard let fromCache else { return true }
        return !(fromCache && isEmpty)
    }
}

// MARK: - Заставка при запуске
// На запуске экран закрыт заставкой, пока не появилась лента: пока приложение собирает интерфейс и ждёт данные,
// нажимать на вкладки и кнопки бессмысленно, а человеку кажется, что приложение зависло.

enum StartupGate {

    /// Сколько секунд заставка закрывает экран, если ленты так и нет (например, нет сети).
    /// Больше времени ожидания сервера в ленте: сначала лента сдаётся сама и показывает, что есть, потом уходит заставка
    static let maxWait: TimeInterval = 14

    /// Через сколько секунд после первого кадра строится основной интерфейс: за это время заставка успевает нарисоваться
    static let buildDelay: TimeInterval = 0.08
}

// MARK: - Подсказка под анимацией загрузки
// Первые секунды достаточно анимации. Если ждать долго, человеку нужно знать, что приложение не зависло.

enum LoadingHint {

    static let slowAfter: TimeInterval = 3
    static let verySlowAfter: TimeInterval = 8

    /// Что написать под анимацией, если ждём уже `waited` секунд. `nil` — ничего
    static func text(waited: TimeInterval) -> String? {
        if waited < slowAfter { return nil }
        if waited < verySlowAfter { return "Связь медленная, подождите немного" }
        return "Всё ещё ждём ответ. Проверьте интернет: данные появятся, как только соединение наладится"
    }
}

// MARK: - Движение мячика
// Мячик летит от одной ракетки к другой по дуге, у ракетки отбивается и летит назад.
// Положение считается по времени, поэтому анимация не зависит от частоты кадров и не копит состояние.

enum RallyMotion {

    /// Сколько секунд мячик летит от одной ракетки к другой
    static let crossingDuration: TimeInterval = 0.9

    /// Какую долю перелёта ракетка, только что отбившая мяч, ещё машет
    static let swingShare: Double = 0.3

    struct Frame: Equatable {
        /// Положение по горизонтали: 0 — у левой ракетки, 1 — у правой
        var x: Double
        /// Высота над столом: 0 — на столе, 1 — высшая точка дуги
        var height: Double
        /// Летит слева направо?
        var movingRight: Bool
        /// Замах левой ракетки: 0 — спокойно, 1 — удар
        var leftSwing: Double
        /// Замах правой ракетки
        var rightSwing: Double

        /// Кадр без движения (для тех, у кого включено «Уменьшение движения»)
        static let resting = Frame(x: 0.5, height: 0.7, movingRight: true, leftSwing: 0, rightSwing: 0)
    }

    // MARK: Числа для Core Animation
    // Рисунок мячика собран из слоёв Core Animation: движение считает система отрисовки, а не приложение,
    // поэтому оно не замирает, когда главный поток занят. Слоям нужны не кадры по времени, а ключевые точки
    // одного цикла; они считаются здесь, чтобы их можно было проверить тестами.

    /// Полный цикл: мячик долетает до правой ракетки и возвращается к левой
    static var cycleDuration: TimeInterval { crossingDuration * 2 }

    /// Какая ракетка бьёт
    enum Paddle {
        case left, right
    }

    /// Высота мячика в `segments + 1` равноотстоящих точках одного перелёта: от 0 через 1 обратно к 0
    static func arcHeights(segments: Int) -> [Double] {
        let count = max(2, segments)
        return (0...count).map { index in
            let progress = Double(index) / Double(count)
            return 4 * progress * (1 - progress)
        }
    }

    /// Замах ракетки за полный цикл: доли цикла (0…1, по возрастанию) и замах в каждой из них
    struct SwingKeyframes: Equatable {
        var times: [Double]
        var values: [Double]
    }

    /// Левая ракетка бьёт в начале цикла, правая на его середине. Удар — рывок: перед ним правая ракетка
    /// за один кадр (около 7 мс) переходит от покоя к замаху, а не наклоняется плавно
    static func swingKeyframes(for paddle: Paddle) -> SwingKeyframes {
        let fade = swingShare / 2      // доля цикла, пока ракетка ещё машет (перелёт — половина цикла)
        let snap = 0.004
        switch paddle {
        case .left:
            return SwingKeyframes(times: [0, fade, 1], values: [1, 0, 0])
        case .right:
            return SwingKeyframes(times: [0, 0.5 - snap, 0.5, 0.5 + fade, 1], values: [0, 0, 1, 0, 0])
        }
    }

    /// Тень мячика на столе: чем выше мячик (`lift` от 0 до 1), тем она у́же и бледнее
    static func shadowScale(lift: Double) -> Double { 1 - 0.4 * lift }

    static func shadowOpacity(lift: Double) -> Double { 0.22 * (1 - 0.6 * lift) }

    /// Кадр через `time` секунд после начала
    static func frame(at time: TimeInterval) -> Frame {
        let seconds = time.isFinite ? max(0, time) : 0
        let crossings = seconds / crossingDuration
        let whole = crossings.rounded(.down)
        let progress = crossings - whole                 // 0…1 внутри текущего перелёта
        let movingRight = whole.truncatingRemainder(dividingBy: 2) == 0

        // Замах: сильнее всего в момент удара, затем затухает
        let swing = max(0, 1 - progress / swingShare)

        return Frame(
            x: movingRight ? progress : 1 - progress,
            height: 4 * progress * (1 - progress),       // дуга: на ракетках 0, над сеткой 1
            movingRight: movingRight,
            leftSwing: movingRight ? swing : 0,
            rightSwing: movingRight ? 0 : swing
        )
    }
}
