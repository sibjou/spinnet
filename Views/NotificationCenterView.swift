import SwiftUI

struct NotificationCenterView: View {
    @ObservedObject var authService: AuthService

    @State private var notifications: [AppNotification] = []
    @State private var isLoading = true
    @State private var selectedFilter: NotificationCategory? = nil  // nil = все
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState

    private let service = NotificationService.shared

    /// Переписка живёт во вкладке «Чаты», здесь её нет
    private var bellNotifications: [AppNotification] {
        NotificationGrouping.visible(notifications)
    }

    var filteredNotifications: [AppNotification] {
        if let filter = selectedFilter {
            return bellNotifications.filter { $0.type.category == filter }
        }
        return bellNotifications
    }

    var unreadCount: Int {
        bellNotifications.filter { !$0.isRead }.count
    }

    /// Разделы фильтра показываются, когда есть из чего выбирать
    private var showsFilter: Bool {
        bellNotifications.count > 5 && uniqueCategories.count > 1
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showsFilter {
                    filterScroll
                }

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if filteredNotifications.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    notificationList
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

    // MARK: - Список по дням
    // Список (а не стопка карточек): только в нём работает смахивание «Удалить»

    private var notificationList: some View {
        let now = Date()
        let sections = FeedGrouping.sections(filteredNotifications, day: { $0.createdAt })
        return List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { notif in
                        notificationCard(notif)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: AppSpacing.xs, leading: AppSpacing.l,
                                                      bottom: AppSpacing.xs, trailing: AppSpacing.l))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteNotification(notif)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text(NotificationGrouping.dayTitle(for: section.day, now: now))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColor.textSecondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Разделы

    private var filterScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.s) {
                filterChip(title: "Все", isSelected: selectedFilter == nil) {
                    selectedFilter = nil
                }

                // Разделы, по которым есть уведомления
                ForEach(uniqueCategories, id: \.self) { category in
                    filterChip(title: category.displayName, isSelected: selectedFilter == category) {
                        selectedFilter = (selectedFilter == category) ? nil : category
                    }
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.vertical, AppSpacing.s)
        }
    }

    private var uniqueCategories: [NotificationCategory] {
        var seen = Set<NotificationCategory>()
        return bellNotifications.compactMap { notif in
            let category = notif.type.category
            if seen.contains(category) { return nil }
            seen.insert(category)
            return category
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : AppColor.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(isSelected ? AppColor.primary : Color(.systemGray6))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Карточка уведомления

    private func notificationCard(_ notif: AppNotification) -> some View {
        Button {
            handleTap(notif)
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.m) {
                leadingIcon(notif)

                // Текст
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(notif.title)
                            .font(.subheadline.weight(notif.isRead ? .regular : .bold))
                            .foregroundColor(AppColor.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: AppSpacing.s)
                        if !notif.isRead {
                            Circle()
                                .fill(AppColor.primary)
                                .frame(width: 8, height: 8)
                                .padding(.top, 5)
                                .accessibilityLabel("Новое")
                        }
                    }

                    Text(notif.body)
                        .font(.subheadline)
                        .foregroundColor(AppColor.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    Text(NotificationGrouping.timeAgo(notif.createdAt))
                        .font(.caption)
                        .foregroundColor(AppColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.m)
            .background(AppColor.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        }
        .buttonStyle(.plain)
    }

    // Слева: аватар человека, который совершил действие (с маленьким значком типа),
    // а если человека нет — просто значок типа
    @ViewBuilder
    private func leadingIcon(_ notif: AppNotification) -> some View {
        if let actorId = notif.actorId, let actorName = notif.actorName, !actorId.isEmpty {
            ZStack(alignment: .bottomTrailing) {
                InitialsAvatar(fullName: actorName, userId: actorId, size: 44)
                Image(systemName: notif.type.icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(colorForType(notif.type))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppColor.cardBackground, lineWidth: 2))
                    .offset(x: 4, y: 4)
            }
            .frame(width: 44, height: 44)
        } else {
            ZStack {
                Circle()
                    .fill(colorForType(notif.type).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: notif.type.icon)
                    .foregroundColor(colorForType(notif.type))
                    .font(.system(size: 18))
            }
        }
    }

    // Один фирменный цвет для всех типов; красным выделена только отмена
    private func colorForType(_ type: NotificationType) -> Color {
        type == .cancellation ? AppColor.danger : AppColor.primary
    }

    // MARK: - Пустое состояние

    private var emptyState: some View {
        EmptyStateView(
            art: .symbol("bell"),
            title: selectedFilter == nil ? "Пока тихо" : "В этом разделе пусто",
            message: selectedFilter == nil
                ? "Здесь появятся напоминания об играх, брони и счёт матчей. Сообщения от игроков — во вкладке «Чаты»."
                : "Выберите «Все», чтобы увидеть остальное.",
            secondaryTitle: selectedFilter == nil ? nil : "Показать все",
            secondaryAction: selectedFilter == nil ? nil : { selectedFilter = nil }
        )
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
        // Переходим к связанному объекту: профиль откроет игру или экран счёта
        appState.handleNotificationTap(type: notif.type.rawValue, targetId: notif.targetId)
        dismiss()
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
}
