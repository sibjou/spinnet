import SwiftUI
import UIKit
import Combine

// MARK: - Анимация загрузки: мячик летает между двумя ракетками
// Вместо маленького серого спиннера, который выглядит как зависший экран.
// Рисунок собран из слоёв Core Animation: движение ведёт система отрисовки, а не приложение.
// Поэтому мячик летает плавно и тогда, когда главный поток занят (запуск, большая загрузка),
// а не замирает вместе с экраном, как замирала бы анимация, которую SwiftUI пересчитывает на каждом кадре.
// Числа движения берутся из `RallyMotion` (там же тесты). При включённом «Уменьшении движения» мячик стоит на месте.

struct PingPongLoader: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RallyLayerRepresentable(reduceMotion: reduceMotion)
            .frame(width: RallyLayerView.sceneSize.width, height: RallyLayerView.sceneSize.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Загрузка")
    }
}

private struct RallyLayerRepresentable: UIViewRepresentable {

    let reduceMotion: Bool

    func makeUIView(context: Context) -> RallyLayerView {
        RallyLayerView(reduceMotion: reduceMotion)
    }

    func updateUIView(_ uiView: RallyLayerView, context: Context) {
        uiView.setReduceMotion(reduceMotion)
    }
}

/// Стол, сетка, две ракетки, мячик и его тень. Сцена та же, что была у SwiftUI-версии: 220 × 104 пункта
final class RallyLayerView: UIView {

    static let sceneSize = CGSize(width: 220, height: 104)

    // Размеры сцены
    private let sideMargin: CGFloat = 34          // от края сцены до центра ракетки
    private let tableTop: CGFloat = 88            // высота поверхности стола
    private let ballSize: CGFloat = 13
    private let arcHeight: CGFloat = 54           // насколько высоко взлетает мячик
    private let paddleHead: CGFloat = 24
    private let handleSize = CGSize(width: 5, height: 11)
    private let paddleOverlap: CGFloat = 2        // ручка заходит под головку
    private let tiltAngle: CGFloat = 28 * .pi / 180
    private let arcSegments = 20                  // на сколько прямых отрезков разбита дуга полёта

    private let table = CALayer()
    private let net = CALayer()
    private let ball = CALayer()
    private let shadow = CALayer()
    private let leftPaddle = PaddleLayers()
    private let rightPaddle = PaddleLayers()
    private var reduceMotion: Bool
    private var activeObservation: AnyCancellable?

    private final class PaddleLayers {
        let container = CALayer()
        let head = CALayer()
        let handle = CALayer()
    }

    // MARK: Создание

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        super.init(frame: CGRect(origin: .zero, size: Self.sceneSize))
        isUserInteractionEnabled = false
        buildLayers()
        updateColors()
        applyStillPose()
        _ = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: RallyLayerView, _: UITraitCollection) in
            view.updateColors()
        }
        // Когда приложение возвращается из фона, система снимает анимации со слоёв: запускаем заново
        activeObservation = NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refreshAnimations() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) не используется")
    }

    override var intrinsicContentSize: CGSize { Self.sceneSize }

    private var paddleHeight: CGFloat { paddleHead + handleSize.height - paddleOverlap }

    private func buildLayers() {
        let tableWidth = Self.sceneSize.width - 24
        table.bounds = CGRect(x: 0, y: 0, width: tableWidth, height: 6)
        table.cornerRadius = 3
        table.position = CGPoint(x: Self.sceneSize.width / 2, y: tableTop + 3)

        net.bounds = CGRect(x: 0, y: 0, width: 2, height: 18)
        net.cornerRadius = 1
        net.position = CGPoint(x: Self.sceneSize.width / 2, y: tableTop - 9)

        for (paddle, centerX) in [(leftPaddle, sideMargin - 8), (rightPaddle, Self.sceneSize.width - sideMargin + 8)] {
            paddle.container.bounds = CGRect(x: 0, y: 0, width: paddleHead, height: paddleHeight)
            // Ракетка качается вокруг низа ручки
            paddle.container.anchorPoint = CGPoint(x: 0.5, y: 1)
            paddle.container.position = CGPoint(x: centerX, y: tableTop - 20 + paddleHeight / 2)
            paddle.head.frame = CGRect(x: 0, y: 0, width: paddleHead, height: paddleHead)
            paddle.head.cornerRadius = paddleHead / 2
            paddle.handle.frame = CGRect(
                x: (paddleHead - handleSize.width) / 2, y: paddleHead - paddleOverlap,
                width: handleSize.width, height: handleSize.height
            )
            paddle.handle.cornerRadius = handleSize.width / 2
            paddle.container.addSublayer(paddle.head)
            paddle.container.addSublayer(paddle.handle)
        }

        shadow.bounds = CGRect(x: 0, y: 0, width: ballSize, height: 3)
        shadow.cornerRadius = 1.5
        ball.bounds = CGRect(x: 0, y: 0, width: ballSize, height: ballSize)
        ball.cornerRadius = ballSize / 2

        for layer in [table, net, leftPaddle.container, rightPaddle.container, shadow, ball] {
            self.layer.addSublayer(layer)
        }
    }

    /// Цвета берутся из дизайн-системы и пересчитываются при смене светлой и тёмной темы
    private func updateColors() {
        let traits = traitCollection
        func resolved(_ color: Color) -> CGColor {
            UIColor(color).resolvedColor(with: traits).cgColor
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        table.backgroundColor = resolved(AppColor.primary.opacity(0.85))
        net.backgroundColor = UIColor.systemGray3.resolvedColor(with: traits).cgColor
        leftPaddle.head.backgroundColor = resolved(AppColor.danger)
        rightPaddle.head.backgroundColor = resolved(AppColor.ink)
        for paddle in [leftPaddle, rightPaddle] {
            paddle.handle.backgroundColor = UIColor(red: 0.62, green: 0.45, blue: 0.28, alpha: 1).cgColor
        }
        shadow.backgroundColor = UIColor.black.cgColor
        ball.backgroundColor = resolved(AppColor.warning)
        CATransaction.commit()
    }

    // MARK: Положение без анимации

    private var leftX: CGFloat { sideMargin }
    private var rightX: CGFloat { Self.sceneSize.width - sideMargin }
    private var ballBaseY: CGFloat { tableTop - ballSize / 2 }

    /// Мячик на одном месте: так выглядит сцена при «Уменьшении движения» и пока анимация не запущена
    private func applyStillPose() {
        let frame = reduceMotion ? RallyMotion.Frame.resting : RallyMotion.frame(at: 0)
        let x = leftX + CGFloat(frame.x) * (rightX - leftX)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ball.position = CGPoint(x: x, y: ballBaseY - arcHeight * CGFloat(frame.height))
        shadow.position = CGPoint(x: x, y: tableTop + 1)
        shadow.transform = CATransform3DMakeScale(CGFloat(RallyMotion.shadowScale(lift: frame.height)), 1, 1)
        shadow.opacity = Float(RallyMotion.shadowOpacity(lift: frame.height))
        leftPaddle.container.transform = CATransform3DMakeRotation(tiltAngle * CGFloat(frame.leftSwing), 0, 0, 1)
        rightPaddle.container.transform = CATransform3DMakeRotation(-tiltAngle * CGFloat(frame.rightSwing), 0, 0, 1)
        CATransaction.commit()
    }

    // MARK: Анимация

    private static let flightKey = "rally.flight"

    func setReduceMotion(_ value: Bool) {
        guard value != reduceMotion else { return }
        reduceMotion = value
        stopAnimations()
        applyStillPose()
        refreshAnimations()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshAnimations()
    }

    /// Анимации идут, пока сцена на экране и движение не отключено. Уже идущие не перезапускаются
    private func refreshAnimations() {
        if window != nil && !reduceMotion {
            if ball.animation(forKey: Self.flightKey) == nil { startAnimations() }
        } else {
            stopAnimations()
            applyStillPose()
        }
    }

    private func stopAnimations() {
        for layer in [ball, shadow, leftPaddle.container, rightPaddle.container] {
            layer.removeAllAnimations()
        }
    }

    private func startAnimations() {
        stopAnimations()
        // Исходное положение слоёв без поворота и сжатия: дальше всё делают анимации
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadow.transform = CATransform3DIdentity
        shadow.opacity = Float(RallyMotion.shadowOpacity(lift: 0))
        leftPaddle.container.transform = CATransform3DIdentity
        rightPaddle.container.transform = CATransform3DIdentity
        CATransaction.commit()

        let crossing = RallyMotion.crossingDuration
        let heights = RallyMotion.arcHeights(segments: arcSegments)
        let keyTimes = heights.indices.map { NSNumber(value: Double($0) / Double(heights.count - 1)) }

        // По горизонтали мячик равномерно летит к правой ракетке и так же возвращается
        let horizontal = CABasicAnimation(keyPath: "position.x")
        horizontal.fromValue = leftX
        horizontal.toValue = rightX
        horizontal.duration = crossing
        horizontal.autoreverses = true
        horizontal.repeatCount = .infinity
        horizontal.timingFunction = CAMediaTimingFunction(name: .linear)

        // По вертикали — дуга: на ракетках мячик у стола, над сеткой выше всего. Дуга одинакова в обе стороны
        let vertical = CAKeyframeAnimation(keyPath: "position.y")
        vertical.values = heights.map { ballBaseY - arcHeight * CGFloat($0) }
        vertical.keyTimes = keyTimes
        vertical.duration = crossing
        vertical.repeatCount = .infinity
        vertical.calculationMode = .linear

        ball.add(horizontal, forKey: Self.flightKey)
        ball.add(vertical, forKey: "rally.arc")

        // Тень идёт под мячиком и меняется вместе с его высотой
        let scale = CAKeyframeAnimation(keyPath: "transform.scale.x")
        scale.values = heights.map { RallyMotion.shadowScale(lift: $0) }
        scale.keyTimes = keyTimes
        scale.duration = crossing
        scale.repeatCount = .infinity
        scale.calculationMode = .linear

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = heights.map { Float(RallyMotion.shadowOpacity(lift: $0)) }
        fade.keyTimes = keyTimes
        fade.duration = crossing
        fade.repeatCount = .infinity
        fade.calculationMode = .linear

        shadow.add(horizontal, forKey: Self.flightKey)
        shadow.add(scale, forKey: "rally.scale")
        shadow.add(fade, forKey: "rally.fade")

        addSwing(to: leftPaddle.container, paddle: .left, direction: 1)
        addSwing(to: rightPaddle.container, paddle: .right, direction: -1)
    }

    /// Ракетка наклоняется к сетке в момент удара и возвращается
    private func addSwing(to layer: CALayer, paddle: RallyMotion.Paddle, direction: CGFloat) {
        let keyframes = RallyMotion.swingKeyframes(for: paddle)
        let swing = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        swing.values = keyframes.values.map { direction * tiltAngle * CGFloat($0) }
        swing.keyTimes = keyframes.times.map { NSNumber(value: $0) }
        swing.duration = RallyMotion.cycleDuration
        swing.repeatCount = .infinity
        swing.calculationMode = .linear
        layer.add(swing, forKey: "rally.swing")
    }
}

// MARK: - Заставка на запуске: закрывает весь экран и не пропускает нажатия

struct StartupOverlay: View {

    var body: some View {
        ZStack {
            AppColor.background
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.s) {
                Text("Spinnet")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.textPrimary)

                LoadingStateView(title: "Готовим ленту…")
            }
        }
        // Окно под заставкой недоступно ни для нажатий, ни для VoiceOver
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isModal)
        .onAppear { Perf.mark("экран: заставка показана") }
    }
}

// MARK: - Экран ожидания: анимация, подпись и подсказка, если ждать долго

struct LoadingStateView: View {

    var title: String = "Загружаем…"

    @State private var startedAt = Date()

    var body: some View {
        VStack(spacing: AppSpacing.l) {
            PingPongLoader()

            Text(title)
                .font(.headline)
                .foregroundColor(AppColor.textPrimary)

            // Раз в секунду проверяем, не пора ли объяснить, что связь медленная
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Text(LoadingHint.text(waited: context.date.timeIntervalSince(startedAt)) ?? " ")
                    .font(.footnote)
                    .foregroundColor(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280, minHeight: 40, alignment: .top)
            }
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}
