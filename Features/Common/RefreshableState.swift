import SwiftUI

// MARK: - Состояние, которое можно потянуть вниз для обновления
// Обычная VStack не прокручивается, а `.refreshable` работает только на прокручиваемом
// содержимом. Поэтому пустой экран («Пока нет турниров») нельзя было обновить жестом.
// Эта обёртка делает его прокручиваемым и растягивает на всю высоту.
struct RefreshableState<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }
}
