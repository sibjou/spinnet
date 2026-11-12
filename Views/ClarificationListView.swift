import SwiftUI
import Combine

// MARK: - ClarificationListView
// Список диалогов по встречам — как в мессенджерах: аватар с точкой «в сети», имя,
// последнее событие, время, галочки «прочитано» и число непрочитанных.
struct ClarificationListView: View {
    @ObservedObject var authService: AuthService
    @EnvironmentObject var appState: AppState

    @StateObject private var service = ClarificationService()
    @StateObject private var presence = PartnerPresenceStore()

    @State private var path: [MeetingClarification] = []
    @State private var pendingDelete: MeetingClarification? = nil
    @State private var showDeleteConfirm = false
    @State private var now = Date()

    private let clockTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var currentUserId: String { authService.currentUserId ?? "" }

    private var partnerIds: Set<String> {
        Set(service.clarifications.map { $0.partnerId(currentUserId: currentUserId) })
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .tabBarInset()
                .navigationTitle("Чаты")
                .navigationDestination(for: MeetingClarification.self) { clarification in
                    ClarificationDetailView(clarification: clarification, authService: authService)
                }
        }
        .onAppear {
            // Подписки живут, пока жива вкладка: при возврате из диалога список не перезапускается
            service.startListening(userId: currentUserId)
            openRequestedClarification()
        }
        .onReceive(clockTimer) { now = $0 }
        .onChange(of: partnerIds, initial: true) { _, ids in presence.watch(ids) }
        .onChange(of: appState.clarificationToOpen) { _, _ in openRequestedClarification() }
        .alert("Удалить диалог?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) { pendingDelete = nil }
            Button("Удалить", role: .destructive) {
                if let item = pendingDelete { service.deleteClarification(id: item.id) }
                pendingDelete = nil
            }
        } message: {
            Text("Переписка будет удалена у обоих участников. Сама встреча останется.")
        }
    }

    // MARK: Содержимое

    @ViewBuilder
    private var content: some View {
        Group {
            if !service.hasLoaded {
                RefreshableState { LoadingStateView(title: "Загружаем встречи…") }
            } else if service.clarifications.isEmpty {
                RefreshableState { emptyState }
            } else {
                list
            }
        }
        .refreshable { await service.refresh(userId: currentUserId) }
    }

    private var list: some View {
        List {
            ForEach(service.clarifications) { clarification in
                NavigationLink(value: clarification) {
                    row(clarification)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = clarification
                        showDeleteConfirm = true
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: Строка диалога

    private func row(_ clarification: MeetingClarification) -> some View {
        let partnerId = clarification.partnerId(currentUserId: currentUserId)
        let name = clarification.partnerName(currentUserId: currentUserId)
        let unread = clarification.unreadCount(for: currentUserId)
        let info = presence.info(for: partnerId)

        return HStack(spacing: 12) {
            OnlineAvatar(
                fullName: name,
                userId: partnerId,
                size: 54,
                isOnline: info.showsOnlineDot(now: now)
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name.isEmpty ? "Партнёр" : name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(ChatTime.listStamp(clarification.activityDate, now: now))
                        .font(.caption)
                        .foregroundColor(unread > 0 ? AppColor.primary : Color.secondary)
                }

                HStack(alignment: .center, spacing: 8) {
                    preview(clarification, partnerId: partnerId, unread: unread)
                    Spacer(minLength: 0)
                    if unread > 0 {
                        UnreadBadge(count: unread)
                    }
                }

                Text(meetingLine(clarification))
                    .font(.caption)
                    .foregroundColor(AppColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }

    /// Последнее событие: «Вы: …» с галочками, если оно моё; без «Вы», если партнёра
    @ViewBuilder
    private func preview(_ clarification: MeetingClarification, partnerId: String, unread: Int) -> some View {
        if clarification.lastActionAt == nil || clarification.lastActionText.isEmpty {
            Text("Пока без сообщений")
                .font(.subheadline)
                .italic()
                .foregroundColor(.secondary)
                .lineLimit(1)
        } else if clarification.lastActionBy == currentUserId {
            HStack(spacing: 4) {
                ReadTicks(
                    isRead: ReadReceipt.isRead(
                        sentAt: clarification.lastActionAt ?? Date(),
                        partnerReadAt: clarification.readAt[partnerId]
                    )
                )
                Text("Вы: \(clarification.lastActionText)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text(clarification.lastActionText)
                .font(.subheadline)
                .foregroundColor(unread > 0 ? Color.primary : Color.secondary)
                .lineLimit(1)
        }
    }

    private func meetingLine(_ clarification: MeetingClarification) -> String {
        let when = "\(ChatTime.dayMonthFull(clarification.sparringDate)), \(clarification.sparringTimeSlot)"
        let city = clarification.sparringCity
        return city.isEmpty ? when : "\(city) · \(when)"
    }

    // MARK: Пустое состояние

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("Пока нет диалогов")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Когда вы забронируете игру или кто-то\nзабронирует вашу, здесь можно будет\nдоговориться о времени и месте")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }

    // MARK: Переход в диалог по уведомлению или из экрана игры

    private func openRequestedClarification() {
        guard let target = appState.clarificationToOpen else { return }
        appState.clarificationToOpen = nil
        path = [target]
    }
}
