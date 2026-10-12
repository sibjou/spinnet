import SwiftUI

struct NotificationCenterView: View {
    @ObservedObject var authService: AuthService

    @State private var notifications: [AppNotification] = []
    @State private var isLoading = true
    @State private var selectedFilter: NotificationType? = nil  // nil = все
    @Environment(\.dismiss) var dismiss

    private let service = NotificationService.shared

    var filteredNotifications: [AppNotification] {
        if let filter = selectedFilter {
            return notifications.filter { $0.type == filter }
        }
        return notifications
    }

    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Фильтр-чипы
                if !notifications.isEmpty {
                    filterScroll
                }

                // Список
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if filteredNotifications.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: AppSpacing.s) {
                            ForEach(filteredNotifications) { notif in
                                notificationCard(notif)
                            }
                        }
                        .padding(AppSpacing.l)
                    }
                }
            }
            .background(AppColor.background)
            .navigationTitle("Уведомления")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if unreadCount > 0 {
                        Button("Прочитать всё") {
                            markAllAsRead()
                        }
                        .font(.subheadline)
                    }
                }
            }
            .onAppear { load() }
        }
    }

    // MARK: - Фильтр-чипы

    private var filterScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.s) {
                filterChip(title: "Все", count: notifications.count, isSelected: selectedFilter == nil) {
                    selectedFilter = nil
                }

                // Уникальные типы из существующих уведомлений
                ForEach(uniqueTypes, id: \.self) { type in
                    let count = notifications.filter { $0.type == type }.count
                    filterChip(
                        title: type.displayName,
                        count: count,
                        isSelected: selectedFilter == type
                    ) {
                        selectedFilter = type
                    }
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.vertical, AppSpacing.s)
        }
        .background(AppColor.cardBackground)
    }

    private var uniqueTypes: [NotificationType] {
        var seen = Set<NotificationType>()
        return notifications.compactMap { notif in
            if seen.contains(notif.type) { return nil }
            seen.insert(notif.type)
            return notif.type
        }
    }

    private func filterChip(title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundColor(isSelected ? .white : AppColor.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.25) : AppColor.background)
                    .cornerRadius(8)
            }
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.s)
            .foregroundColor(isSelected ? .white : AppColor.textPrimary)
            .background(isSelected ? AppColor.primary : AppColor.background)
            .cornerRadius(AppRadius.medium)
        }
    }

    // MARK: - Карточка уведомления

    private func notificationCard(_ notif: AppNotification) -> some View {
        Button {
            handleTap(notif)
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.m) {
                // Иконка слева
                ZStack {
                    Circle()
                        .fill(colorForType(notif.type).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: notif.type.icon)
                        .foregroundColor(colorForType(notif.type))
                        .font(.system(size: 18))
                }

                // Текст
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(notif.title)
                            .font(.subheadline.bold())
                            .foregroundColor(AppColor.textPrimary)
                        Spacer()
                        if !notif.isRead {
                            Circle()
                                .fill(AppColor.primary)
                                .frame(width: 8, height: 8)
                        }
                    }

                    Text(notif.body)
                        .font(.subheadline)
                        .foregroundColor(AppColor.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    Text(timeAgo(notif.createdAt))
                        .font(.caption)
                        .foregroundColor(AppColor.textTertiary)
                }
            }
            .padding(AppSpacing.m)
            .background(notif.isRead ? AppColor.cardBackground : AppColor.cardBackground.opacity(0.8))
            .cornerRadius(AppRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .stroke(notif.isRead ? Color.clear : AppColor.primary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteNotification(notif)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    private func colorForType(_ type: NotificationType) -> Color {
        switch type.iconColor {
        case "primary": return AppColor.primary
        case "warning": return AppColor.warning
        case "danger":  return AppColor.danger
        case "info":    return AppColor.info
        case "star":    return AppColor.star
        default:        return AppColor.primary
        }
    }

    // MARK: - Пустое состояние

    private var emptyState: some View {
        VStack(spacing: AppSpacing.m) {
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundColor(AppColor.textTertiary)
            Text("Нет уведомлений")
                .font(.title3.bold())
                .foregroundColor(AppColor.textSecondary)
            Text(selectedFilter == nil
                 ? "Здесь будут появляться важные события"
                 : "Нет уведомлений в этой категории")
                .font(.subheadline)
                .foregroundColor(AppColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(AppSpacing.xxl)
    }

    // MARK: - Действия

    private func load() {
        guard let userId = authService.currentUserId else { return }
        service.loadNotifications(userId: userId) { items in
            notifications = items
            isLoading = false
        }
    }

    private func handleTap(_ notif: AppNotification) {
        // Помечаем как прочитанное
        if !notif.isRead, let userId = authService.currentUserId {
            service.markAsRead(userId: userId, notificationId: notif.id)
            load()
        }
        // TODO: навигация к связанному объекту через AppState
    }

    private func markAllAsRead() {
        guard let userId = authService.currentUserId else { return }
        service.markAllAsRead(userId: userId) {
            load()
        }
    }

    private func deleteNotification(_ notif: AppNotification) {
        guard let userId = authService.currentUserId else { return }
        service.deleteNotification(userId: userId, notificationId: notif.id)
        notifications.removeAll { $0.id == notif.id }
    }

    // MARK: - Время "назад"

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "только что" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) мин назад" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) ч назад" }
        let days = hours / 24
        if days < 7 { return "\(days) дн назад" }

        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}
