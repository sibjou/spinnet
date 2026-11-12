import SwiftUI
import FirebaseFirestore

// MARK: - ProfileView
// Главный экран профиля пользователя.
// Структура:
//  Шапка: аватар, имя, город, бейджи характеристик, статистика
//  Кнопка редактирования профиля
//  Переключатель из 4 вкладок: Игры | Статистика | Участвую | Организую
//  Содержимое выбранной вкладки со сворачиваемыми секциями

struct ProfileView: View {
    
    @State var completedParticipationCount = 0
    @State var completedCreatedCount = 0
    @State var historyLoaded = false
    @State var averageRating: Double = 0
    @State var reviewsCount: Int = 0
    @State var tournamentsCount: Int = 0
    @State var showReviewsList = false
    @State var showNotifications = false
    @ObservedObject var notificationService = NotificationService.shared
    
    // MARK: - Зависимости
    
    
    @ObservedObject var authService: AuthService
    @EnvironmentObject var appState: AppState
    @StateObject var sparringService   = SparringService()
    @StateObject var matchesStore      = PlayerMatchesStore()
    @StateObject var tournamentService = TournamentService()

    // MARK: - Состояние UI

    @State var collapsedSections: Set<String> = [
        "games_history",
        "part_completed",
        "created_completed"
    ]

    // Какая вкладка выбрана: 0 = Игры, 1 = Статистика, 2 = Участвую, 3 = Организую
    @State var selectedTab = 0

    // Фильтры и сортировка истории игр
    @State var historyFilter = GameHistoryFilter()

    // MARK: - Состояние модальных экранов

    @State var editingRequestId: String? = nil   // открыть редактирование заявки
    @State var bookedGameId: String?    = nil    // открыть детали забронированной игры
    @State var bookedGameData: [String: Any] = [:]
    @State var bookedGameOpensMatch = false      // открыть сразу экран счёта (по уведомлению)
    @State var bookedGameOpensReview = false     // открыть сразу форму отзыва (по уведомлению)
    @State var profileToOpen: String? = nil      // открыть профиль человека (по уведомлению об отмене)
    @State var showSettings    = false
    @State var showEditProfile = false

    // MARK: - Данные

    @State var userData: [String: Any] = [:]
    @State var isLoadingProfile = true
    @State var completedParticipationTournaments: [[String: Any]] = []
    @State var completedCreatedTournaments: [[String: Any]] = []
    // Незавершённые турниры (предстоящие и идущие): приходят теми же двумя запросами, что и завершённые
    @State var activeParticipationTournaments: [[String: Any]] = []
    @State var activeCreatedTournaments: [[String: Any]] = []

    // Профиль открывают часто (вкладка, возврат из окон), но данные не должны перечитываться чаще раза в несколько секунд
    @State var loadPolicy = RefreshPolicy(minInterval: 5)

    // MARK: - Тело

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.l) {

                    profileHeader

                    // Кнопку редактирования отсюда убрали — теперь карандашик в шапке
                    
                    tabSelector
                        .padding(.horizontal, AppSpacing.l)

                    tabContent
                        .padding(.horizontal, AppSpacing.l)
                }
                .padding(.vertical, AppSpacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .tabBarInset()
            .background(AppColor.background)
            .navigationTitle("Профиль")
            .toolbar {
                // Колокольчик с бейджем — слева
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showNotifications = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            // Невидимый расширенный контейнер чтобы бейдж не обрезался
                            Color.clear
                                .frame(width: 32, height: 28)
                                .overlay(
                                    Image(systemName: "bell")
                                        .font(.body)
                                        .foregroundColor(AppColor.textPrimary)
                                        .frame(width: 24, height: 24, alignment: .center)
                                    , alignment: .leading
                                )

                            if notificationService.unreadCountValue > 0 {
                                Text(notificationService.unreadCountValue > 9 ? "9+" : "\(notificationService.unreadCountValue)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(AppColor.danger)
                                    .clipShape(Capsule())
                                    .offset(x: -2, y: -4)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(notificationService.unreadCountValue > 0
                                        ? "Уведомления, новых: \(notificationService.unreadCountValue)"
                                        : "Уведомления")
                }

                // Редактирование + настройки — справа
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: AppSpacing.l) {
                        Button {
                            showEditProfile = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.body)
                                .foregroundColor(AppColor.textPrimary)
                        }
                        .accessibilityLabel("Редактировать профиль")

                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.body)
                                .foregroundColor(AppColor.textPrimary)
                        }
                        .accessibilityLabel("Настройки")
                    }
                }
            }
            // Настройки
            .sheet(isPresented: $showNotifications) {
                NotificationCenterView(authService: authService)
                    .onDisappear {
                        if let userId = authService.currentUserId {
                            notificationService.refreshUnreadCount(userId: userId)
                        }
                    }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(authService: authService)
            }
            // Редактирование своей активной заявки
            .sheet(item: Binding(
                get: { editingRequestId.map { IdentifiableString(id: $0) } },
                set: { editingRequestId = $0?.id }
            )) { wrapper in
                EditRequestView(
                    requestId: wrapper.id,
                    isPresented: Binding(
                        get: { editingRequestId != nil },
                        set: { if !$0 { editingRequestId = nil } }
                    ),
                    onUpdate: { loadAllData(force: true) }
                )
            }
            // Детали забронированной/завершённой игры
            .sheet(item: Binding(
                get: { bookedGameId.map { IdentifiableString(id: $0) } },
                set: { bookedGameId = $0?.id }
            ), onDismiss: {
                bookedGameOpensMatch = false
                bookedGameOpensReview = false
                if let userId = authService.currentUserId {
                    matchesStore.load(userId: userId, force: true)
                }
            }) { _ in
                BookedGameDetailView(
                    game: bookedGameData,
                    authService: authService,
                    sparringService: sparringService,
                    isPresented: Binding(
                        get: { bookedGameId != nil },
                        set: { if !$0 { bookedGameId = nil } }
                    ),
                    autoOpenMatch: bookedGameOpensMatch,
                    autoOpenReview: bookedGameOpensReview
                )
            }
            // Профиль другого игрока (переход по уведомлению)
            .sheet(item: Binding(
                get: { profileToOpen.map { IdentifiableString(id: $0) } },
                set: { profileToOpen = $0?.id }
            )) { wrapper in
                NavigationStack {
                    PlayerProfileView(userId: wrapper.id)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Закрыть") { profileToOpen = nil }
                            }
                        }
                }
            }
            // Редактирование профиля
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(
                    authService: authService,
                    isPresented: $showEditProfile,
                    onUpdate: { loadAllData(force: true) }
                )
            }
            // Список отзывов
            .sheet(isPresented: $showReviewsList) {
                if let userId = authService.currentUserId {
                    NavigationStack {
                        ReviewsListView(
                            userId: userId,
                            userName: "\(userData["firstName"] as? String ?? "") \(userData["lastName"] as? String ?? "")"
                        )
                    }
                }
            }
            .onAppear {
                Perf.mark("профиль: открыт")
                loadAllData()
                openPendingNotificationTarget()
            }
            .onChange(of: appState.pendingNotificationTarget) { _, _ in
                openPendingNotificationTarget()
            }
            // Вкладки остаются в памяти: вернулись в профиль — данные показываются сразу, а свежие подгружаются фоном
            .onChange(of: appState.selectedTab) { _, tab in
                if tab == .profile { loadAllData() }
            }
            // Изменили турнир на его странице (записались, завершили…) — обновляем списки в профиле
            .onChange(of: tournamentService.changeCounter) { _, _ in
                if let userId = authService.currentUserId { loadMyTournaments(userId: userId) }
            }
            // «Мой профиль» из чужой страницы: закрываем все открытые окна
            .onChange(of: appState.dismissSignal) { _, _ in
                bookedGameId = nil
                showReviewsList = false
                profileToOpen = nil
                showNotifications = false
            }
        }
    }

    // MARK: - Переключатель вкладок
    // Pill-стиль как в современных iOS-приложениях

    // Тот же переключатель использует чужой профиль (PlayerProfileView)
    var tabSelector: some View {
        ProfileTabBar(
            items: [
                .init(id: 0, title: "Игры",       icon: "sportscourt.fill"),
                .init(id: 1, title: "Статистика", icon: "chart.bar.xaxis"),
                .init(id: 2, title: "Участвую",   icon: "person.fill.checkmark"),
                .init(id: 3, title: "Организую",  icon: "crown.fill")
            ],
            selection: $selectedTab
        )
    }

    // MARK: - Маршрутизатор содержимого вкладки

    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case 0: myGamesTab
        case 1: myStatsTab
        case 2: myTournamentsParticipationTab
        case 3: myCreatedTournamentsTab
        default: EmptyView()
        }
    }

    // MARK: - Управление сворачиваемыми секциями

    // Свёрнута ли секция с данным ключом
    func isCollapsed(_ key: String) -> Bool {
        collapsedSections.contains(key)
    }

    // Переключить состояние секции с анимацией
    func toggleSection(_ key: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if collapsedSections.contains(key) {
                collapsedSections.remove(key)
                // Подгружаем тяжёлые данные при первом раскрытии
                loadDataForSection(key)
            } else {
                collapsedSections.insert(key)
            }
        }
    }

    // Подгрузка данных при раскрытии секции
    func loadDataForSection(_ key: String) {
        guard let userId = authService.currentUserId else { return }

        switch key {
        case "games_history":
            if !historyLoaded {
                sparringService.loadMyCompletedGames(userId: userId)
                historyLoaded = true
            }
        case "part_completed", "created_completed":
            break   // завершённые турниры уже загружены в loadMyTournaments
        default:
            break
        }
    }

    // MARK: - Загрузка данных

    // Главная функция загрузки — вызывается при открытии вкладки и после редактирований.
    // `force` — после правок: данные изменились, ждать нельзя.
    func loadAllData(force: Bool = false) {
        guard let userId = authService.currentUserId, loadPolicy.shouldRun(force: force) else { return }

        // Сначала проверяем статусы (вдруг что-то завершилось пока приложение было закрыто)
        StatusManager.shared.checkAllStatuses()
        
        // Обновляем счётчик уведомлений
            NotificationService.shared.refreshUnreadCount(userId: userId)

        // Загружаем данные текущего пользователя
        UserService.shared.fetchUser(id: userId) { data in
            isLoadingProfile = false
            userData = data ?? [:]
        }

        // Загружаем активные заявки и предстоящие игры
        sparringService.loadAll(userId: userId)
        
        sparringService.loadCompletedGamesCount(userId: userId)

        // Матчи со счётом: для вкладки «Статистика» и отметок на карточках игр
        matchesStore.load(userId: userId, force: true)

        // Мои турниры (участвую / организую): два точечных запроса по моему id
        loadMyTournaments(userId: userId)

        // Завершённые турниры приходят вместе с loadMyTournaments. История игр грузится только когда
        // её раскрыли (см. loadDataForSection) — но если уже раскрывали, держим её свежей
        if historyLoaded {
            sparringService.loadMyCompletedGames(userId: userId)
        }

        // Загружаем рейтинг и количество отзывов
            Perf.begin("профиль: рейтинг и отзывы")
            ReviewService().loadRatingStats(forUserId: userId) { avg, count in
                self.averageRating = avg
                self.reviewsCount = count
                Perf.end("профиль: рейтинг и отзывы")
                Perf.mark("профиль: данные загружены")
            }
        
    }
    
    // Турниры пользователя: счётчики и списки завершённых.
    // Два точечных запроса (участник / организатор) вместо чтения всей коллекции.
    func loadMyTournaments(userId: String) {
        tournamentService.loadUserTournaments(userId: userId) { participating, organizing in
            let completedParticipating = participating.filter { ($0["status"] as? String) == "completed" }
            let completedOrganizing    = organizing.filter    { ($0["status"] as? String) == "completed" }
            let activeStatuses: Set<String> = ["upcoming", "in_progress"]
            activeParticipationTournaments = participating.filter { activeStatuses.contains($0["status"] as? String ?? "") }
            activeCreatedTournaments       = organizing.filter    { activeStatuses.contains($0["status"] as? String ?? "") }

            let allIds = Set((participating + organizing).compactMap { $0["documentId"] as? String })

            tournamentsCount = allIds.count
            completedParticipationTournaments = completedParticipating
            completedCreatedTournaments = completedOrganizing
            completedParticipationCount = completedParticipating.count
            completedCreatedCount = completedOrganizing.count
        }
    }

    // MARK: - Вспомогательная структура
    // Нужна для sheet(item:) — он требует Identifiable, а String им не является

    struct IdentifiableString: Identifiable {
        let id: String
    }
}
