import SwiftUI
import Combine
import UIKit

struct MainTabView: View {
    @ObservedObject var authService: AuthService
    @EnvironmentObject var appState: AppState

    // Пока открыта клавиатура, панель вкладок прячется: иначе SwiftUI поднимает её над клавиатурой
    // и она закрывает поле ввода (например, поиск в истории профиля)
    @State private var isKeyboardVisible    = false
    @State private var showCreateSheet      = false
    @State private var showCreateRequest    = false
    @State private var showCreateTournament = false
    @ObservedObject private var notificationService = NotificationService.shared
    @ObservedObject private var connection = ConnectionMonitor.shared
    @StateObject private var clarificationService = ClarificationService()
    @StateObject private var tournamentService = TournamentService()

    // Вкладки, которые уже открывали. Они остаются в памяти: переключение не пересоздаёт экран,
    // не заводит заново подписки и не показывает «Загрузка…» — человек возвращается туда, где был.
    // Нетронутые вкладки не создаются совсем, поэтому на запуске грузится только лента.
    @State private var visitedTabs: Set<AppTab> = [.feed]

    // Заставка при запуске: пока лента не показана, экран закрыт, а нажатия не проходят
    @State private var isInterfaceBuilt = false
    @State private var isStartupDone    = false

    /// Основной интерфейс: вкладки. Панель вкладок вставляет в себя каждая вкладка (см. TabBarInset)
    private var tabs: some View {
        ZStack {
            ForEach(AppTab.allCases, id: \.self) { tab in
                if visitedTabs.contains(tab) {
                    tabContent(tab)
                        .opacity(appState.selectedTab == tab ? 1 : 0)
                        .allowsHitTesting(appState.selectedTab == tab)
                        .accessibilityHidden(appState.selectedTab != tab)
                }
            }
        }
        .environment(\.tabBarContent, isKeyboardVisible ? nil : AnyView(customTabBar))
        .onAppear { Perf.mark("экран: вкладки на экране") }
    }

    var body: some View {
        let _ = Perf.mark("экран: MainTabView собирается")
        ZStack {
            // Тяжёлый интерфейс строится не в первом кадре, а сразу после него: заставка появляется мгновенно
            if isInterfaceBuilt {
                tabs
            }
            if !isStartupDone {
                StartupOverlay()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isStartupDone)
        .connectionNotice()
        .task { await runStartup() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .sheet(isPresented: $showCreateRequest) {
            CreateRequestView(authService: authService)
        }
        .sheet(isPresented: $showCreateTournament) {
            CreateTournamentView(
                authService: authService,
                tournamentService: tournamentService,
                isPresented: $showCreateTournament
            )
        }
        // «+» одинаково работает на любом экране: можно создать и заявку, и турнир
        .confirmationDialog("Что создаём?", isPresented: $showCreateSheet, titleVisibility: .visible) {
            Button("🏓  Заявку на спарринг") { showCreateRequest    = true }
            Button("🏆  Турнир")             { showCreateTournament = true }
            Button("Отмена", role: .cancel)  {}
        }
        .onAppear { Perf.mark("экран: MainTabView появился") }
        .onDisappear {
            // Выход из аккаунта: слушатели должны остановиться, иначе они продолжат
            // читать данные прежнего пользователя и получат «Missing or insufficient permissions»
            clarificationService.stopUnreadListener()
            notificationService.stopUnreadListener()
        }
        // Вкладка запоминается как открытая
        .onChange(of: appState.selectedTab, initial: true) { _, tab in
            visitedTabs.insert(tab)
        }
    }

    /// Первый кадр — только заставка, затем строится интерфейс. Если ленты так и нет, заставка уходит сама
    private func runStartup() async {
        appState.isStartupDone = false
        try? await Task.sleep(nanoseconds: UInt64(StartupGate.buildDelay * 1_000_000_000))
        Perf.mark("экран: строим основной интерфейс")
        isInterfaceBuilt = true
        Perf.mark("экран: основной интерфейс создан")

        try? await Task.sleep(nanoseconds: UInt64(StartupGate.maxWait * 1_000_000_000))
        finishStartup()
    }

    private func finishStartup() {
        guard !isStartupDone else { return }
        isStartupDone = true
        appState.isStartupDone = true
        Perf.mark("экран: заставка снята")
        startUnreadListeners()
    }

    /// Счётчики непрочитанного на вкладках не нужны для первого экрана: запускаются, когда лента уже показана
    private func startUnreadListeners() {
        guard let userId = authService.currentUserId else { return }
        notificationService.startUnreadListener(userId: userId)
        clarificationService.startUnreadListener(currentUserId: userId)
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .feed:
            FeedView(authService: authService, onContentShown: finishStartup)
        case .tournaments:
            TournamentListView(authService: authService)
        case .chat:
            ChatListView(authService: authService)
        case .profile:
            ProfileView(authService: authService)
        }
    }

    // MARK: - Панель вкладок

    private var customTabBar: some View {
        VStack(spacing: 0) {
            // Пока сети нет, над панелью висит полоса: человек видит, что лента из сохранённых данных
            if !connection.isOnline {
                OfflineStatusBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            ZStack {
                HStack(spacing: 0) {
                    tabBarButton(icon: "figure.table.tennis", title: "Лента", tab: .feed)
                    tabBarButton(icon: "trophy.fill", title: "Турниры", tab: .tournaments)
                    Spacer().frame(maxWidth: .infinity)
                    tabBarButton(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Чаты",
                        tab: .chat,
                        badgeCount: clarificationService.unreadClarificationsCount
                    )
                    tabBarButton(
                        icon: "person.crop.circle.fill",
                        title: "Профиль",
                        tab: .profile,
                        badgeCount: notificationService.unreadCountValue
                    )
                }

                Button { showCreateSheet = true } label: {
                    ZStack {
                        Circle()
                            .fill(AppColor.primary)
                            .frame(width: 50, height: 50)
                            .shadow(color: AppColor.primary.opacity(0.35), radius: 8, y: 4)
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .offset(y: -8) // насколько плюс выступает вверх
                .accessibilityLabel("Создать")
                .accessibilityHint("Заявку на спарринг или турнир")
            }
            .frame(height: 49)
        }
        // Фон доходит до нижнего края экрана, под индикатор «домой»
        .background(Color(.systemBackground).ignoresSafeArea(edges: .bottom))
        .animation(.easeInOut(duration: 0.25), value: connection.isOnline)
        .onAppear { Perf.mark("экран: панель вкладок на экране") }
    }

    private func tabBarButton(icon: String, title: String, tab: AppTab, badgeCount: Int = 0) -> some View {
        let isSelected = appState.selectedTab == tab
        return Button { appState.selectedTab = tab } label: {
            VStack(spacing: 3) {
                // Иконка с возможным красным бейджем с числом
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 19))

                    if badgeCount > 0 {
                        Text(badgeCount > 9 ? "9+" : "\(badgeCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(AppColor.danger)
                            .clipShape(Capsule())
                            .offset(x: 10, y: -6)
                    }
                }

                // Подписи не меньше 11 pt и не растут выше «крупного» размера, чтобы панель не ломалась
                Text(title)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .dynamicTypeSize(...DynamicTypeSize.large)
            }
            // Выбранная вкладка — акцентным цветом, остальные — читаемым серым
            .foregroundColor(isSelected ? AppColor.primary : Color(.secondaryLabel))
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(badgeCount > 0 ? "\(title), новых: \(badgeCount)" : title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
