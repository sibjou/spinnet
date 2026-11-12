import SwiftUI

// MARK: - Панель вкладок как часть экрана
// Панель живёт внутри корневого экрана каждой вкладки (нижний отступ безопасной области).
// Когда поверх открывается другой экран (диалог, турнир), он закрывает и панель обычной анимацией
// перехода — состояния «спрятать панель» нет, поэтому нет и пустой полосы, которая оставалась,
// пока приложение не успевало пересчитать отступы посреди перехода.

private struct TabBarContentKey: EnvironmentKey {
    static var defaultValue: AnyView? { nil }
}

extension EnvironmentValues {
    /// Панель вкладок; задаётся один раз в MainTabView, подставляется корневыми экранами вкладок
    var tabBarContent: AnyView? {
        get { self[TabBarContentKey.self] }
        set { self[TabBarContentKey.self] = newValue }
    }
}

private struct TabBarInset: ViewModifier {
    @Environment(\.tabBarContent) private var bar

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if let bar { bar }
        }
    }
}

extension View {
    /// Ставит панель вкладок под содержимое корневого экрана вкладки.
    /// Экраны, открытые поверх (push), этот модификатор не вызывают и панель закрывают.
    func tabBarInset() -> some View {
        modifier(TabBarInset())
    }
}
