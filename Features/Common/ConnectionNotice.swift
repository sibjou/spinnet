import SwiftUI

// MARK: - Что видит человек, когда нет сети

/// Узкая полоса над панелью вкладок, пока сети нет
struct OfflineStatusBar: View {

    static let height: CGFloat = 24

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
            Text(ConnectionRule.offlineStatus)
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(Color(.systemBackground))
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(Color(.label))
        .accessibilityElement(children: .combine)
    }
}

/// Пояснение сверху экрана: «Нет интернета. Действие не выполнено…». Исчезает само
struct ConnectionNoticeView: View {

    @ObservedObject private var connection = ConnectionMonitor.shared
    @State private var hostID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            if connection.topHost == hostID, let notice = connection.notice {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                    Text(notice)
                        .multilineTextAlignment(.leading)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Color(.systemBackground))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.label), in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.black.opacity(0.2), radius: 8, y: 3)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.25), value: connection.notice)
        .allowsHitTesting(false)
        .onAppear { connection.register(host: hostID) }
        .onDisappear { connection.unregister(host: hostID) }
    }
}

extension View {

    /// Показывает пояснение об отказе без сети поверх этого экрана. Лист показывается отдельным слоем поверх
    /// экрана, поэтому модификатор нужен и на корне каждого листа, где есть действия с записью
    func connectionNotice() -> some View {
        overlay(alignment: .top) { ConnectionNoticeView() }
    }
}
