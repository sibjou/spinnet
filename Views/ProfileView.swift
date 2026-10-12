import SwiftUI
import FirebaseFirestore

// MARK: - ProfileView
// Главный экран профиля пользователя.
// Структура:
//  Шапка: аватар, имя, город, бейджи характеристик, статистика
//  Кнопка редактирования профиля
//  Переключатель из 3 вкладок: Игры | Участвую | Создаю
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
    @StateObject var sparringService   = SparringService()
    @StateObject var tournamentService = TournamentService()

    // MARK: - Состояние UI

    @State var collapsedSections: Set<String> = [
        "games_history",
        "part_completed",
        "created_completed"
    ]

    // Какая вкладка выбрана: 0 = Игры, 1 = Участвую, 2 = Создаю
    @State var selectedTab = 0

    // MARK: - Состояние модальных экранов

    @State var editingRequestId: String? = nil   // открыть редактирование заявки
    @State var bookedGameId: String?    = nil    // открыть детали забронированной игры
    @State var bookedGameData: [String: Any] = [:]
    @State var showSettings    = false
    @State var showEditProfile = false

    // MARK: - Данные

    @State var userData: [String: Any] = [:]
    @State var isLoadingProfile = true
    @State var completedParticipationTournaments: [[String: Any]] = []
    @State var completedCreatedTournaments: [[String: Any]] = []

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

                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.body)
                                .foregroundColor(AppColor.textPrimary)
                        }
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
                    onUpdate: { loadAllData() }
                )
            }
            // Детали забронированной/завершённой игры
            .sheet(item: Binding(
                get: { bookedGameId.map { IdentifiableString(id: $0) } },
                set: { bookedGameId = $0?.id }
            )) { _ in
                BookedGameDetailView(
                    game: bookedGameData,
                    authService: authService,
                    sparringService: sparringService,
                    isPresented: Binding(
                        get: { bookedGameId != nil },
                        set: { if !$0 { bookedGameId = nil } }
                    )
                )
            }
            // Редактирование профиля
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(
                    authService: authService,
                    isPresented: $showEditProfile,
                    onUpdate: { loadAllData() }
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
            .onAppear { loadAllData() }
        }
    }

    // MARK: - Переключатель вкладок
    // Pill-стиль как в современных iOS-приложениях

    var tabSelector: some View {
        HStack(spacing: 0) {
            tabButton(title: "Игры",     icon: "sportscourt.fill",       index: 0)
            tabButton(title: "Участвую", icon: "person.fill.checkmark", index: 1)
            tabButton(title: "Создаю",   icon: "crown.fill",             index: 2)
        }
        .padding(4)
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.medium)
    }

    func tabButton(title: String, icon: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.s)
            .background(selectedTab == index ? AppColor.background : Color.clear)
            .foregroundColor(selectedTab == index ? AppColor.primary : AppColor.textSecondary)
            .cornerRadius(AppRadius.small)
        }
    }

    // MARK: - Маршрутизатор содержимого вкладки

    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case 0: myGamesTab
        case 1: myTournamentsParticipationTab
        case 2: myCreatedTournamentsTab
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

    // Главная функция загрузки — вызывается при .onAppear и после редактирований
    func loadAllData() {
        guard let userId = authService.currentUserId else { return }

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

        // Загружаем активные турниры (upcoming + in_progress)
        tournamentService.loadTournaments()
        
        loadMyTournaments(userId: userId)

        // Завершённые турниры и история игр НЕ загружаются здесь —
        // они подгружаются только когда пользователь раскрывает соответствующую секцию
        // (см. loadDataForSection)
        
        // Загружаем рейтинг и количество отзывов
            ReviewService().loadRatingStats(forUserId: userId) { avg, count in
                self.averageRating = avg
                self.reviewsCount = count
            }
        
    }
    
    // Турниры пользователя: счётчики и списки завершённых.
    // Два точечных запроса (участник / организатор) вместо чтения всей коллекции.
    func loadMyTournaments(userId: String) {
        tournamentService.loadUserTournaments(userId: userId) { participating, organizing in
            let completedParticipating = participating.filter { ($0["status"] as? String) == "completed" }
            let completedOrganizing    = organizing.filter    { ($0["status"] as? String) == "completed" }

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
