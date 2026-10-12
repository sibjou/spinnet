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
    
    @State private var completedParticipationCount = 0
    @State private var completedCreatedCount = 0
    @State private var historyLoaded = false
    @State private var completedTournamentsLoaded = false
    @State private var averageRating: Double = 0
    @State private var reviewsCount: Int = 0
    @State private var tournamentsCount: Int = 0
    @State private var showReviewsList = false
    @State private var showNotifications = false
    @ObservedObject private var notificationService = NotificationService.shared
    
    // MARK: - Зависимости
    
    
    @ObservedObject var authService: AuthService
    @StateObject private var sparringService   = SparringService()
    @StateObject private var tournamentService = TournamentService()

    // MARK: - Состояние UI

    @State private var collapsedSections: Set<String> = [
        "games_history",
        "part_completed",
        "created_completed"
    ]

    // Какая вкладка выбрана: 0 = Игры, 1 = Участвую, 2 = Создаю
    @State private var selectedTab = 0

    // MARK: - Состояние модальных экранов

    @State private var editingRequestId: String? = nil   // открыть редактирование заявки
    @State private var bookedGameId: String?    = nil    // открыть детали забронированной игры
    @State private var bookedGameData: [String: Any] = [:]
    @State private var showSettings    = false
    @State private var showEditProfile = false

    // MARK: - Данные

    @State private var userData: [String: Any] = [:]
    @State private var isLoadingProfile = true
    @State private var completedParticipationTournaments: [[String: Any]] = []
    @State private var completedCreatedTournaments: [[String: Any]] = []

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

    // MARK: - Шапка профиля
    // Аватар + имя + город + бейджи + статистика

    private var profileHeader: some View {
        VStack(spacing: AppSpacing.m) {
            // Аватар
            Image(systemName: "person.circle.fill")
                .font(.system(size: AppSize.avatarLarge))
                .foregroundColor(AppColor.primary)

            // Имя
            Text("\(userData["firstName"] as? String ?? "") \(userData["lastName"] as? String ?? "")")
                .font(.title2.bold())
                .foregroundColor(AppColor.textPrimary)

            // Город
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .font(.caption)
                    .foregroundColor(AppColor.primary)
                Text(userData["city"] as? String ?? "")
                    .font(.subheadline)
                    .foregroundColor(AppColor.textSecondary)
            }

            // Характеристики
            HStack(spacing: AppSpacing.s) {
                infoBadge(userData["skillLevel"] as? String ?? "")
                infoBadge(userData["grip"]       as? String ?? "")
                infoBadge(userData["playStyle"]  as? String ?? "")
            }

            // Блок статистики — 4 элемента
            statsBlock
                .padding(.horizontal, AppSpacing.l)
                .padding(.top, AppSpacing.s)
        }
    }

    // MARK: - Блок статистики

    private var statsBlock: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statItem(
                    value: "\(sparringService.completedGamesCount)",
                    title: "игр"
                )
                Divider().frame(height: 40)
                statItem(
                    value: "\(tournamentsCount)",
                    title: "турниров"
                )
                Divider().frame(height: 40)
                statItem(
                    value: ttwRatingDisplay,
                    title: "TTW"
                )
                Divider().frame(height: 40)

                // Кликабельный блок отзывов
                Button {
                    showReviewsList = true
                } label: {
                    ratingItem
                }
            }
            .padding(.vertical, AppSpacing.m)
            .background(AppColor.cardBackground)
            .cornerRadius(AppRadius.medium)
        }
    }

    // Обычный блок (некликабельный)
    private func statItem(value: String, title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(AppColor.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundColor(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // Блок отзывов — со звездой
    private var ratingItem: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundColor(AppColor.star)
                Text(reviewsCount > 0 ? String(format: "%.1f", averageRating) : "—")
                    .font(.title3.bold())
                    .foregroundColor(AppColor.textPrimary)
            }
            Text(reviewsCount > 0 ? "\(reviewsCount) \(reviewsWord(reviewsCount))" : "отзывы")
                .font(.caption)
                .foregroundColor(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // TTW: либо число, либо прочерк
    private var ttwRatingDisplay: String {
        if let rating = userData["ttwRating"] as? Int, rating > 0 {
            return "\(rating)"
        }
        return "—"
    }

    // Склонение слова "отзыв"
    private func reviewsWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 14 { return "отзывов" }
        switch mod10 {
        case 1: return "отзыв"
        case 2, 3, 4: return "отзыва"
        default: return "отзывов"
        }
    }

    // Маленький серый бейдж для характеристики (уровень, хват, стиль)
    private func infoBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(AppColor.textPrimary)
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColor.cardBackground)
            .cornerRadius(AppRadius.small)
    }

    // Блок в статистике: крупное значение + подпись
    private func statBlock(value: String, title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(AppColor.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundColor(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Переключатель вкладок
    // Pill-стиль как в современных iOS-приложениях

    private var tabSelector: some View {
        HStack(spacing: 0) {
            tabButton(title: "Игры",     icon: "sportscourt.fill",       index: 0)
            tabButton(title: "Участвую", icon: "person.fill.checkmark", index: 1)
            tabButton(title: "Создаю",   icon: "crown.fill",             index: 2)
        }
        .padding(4)
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.medium)
    }

    private func tabButton(title: String, icon: String, index: Int) -> some View {
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
    private var tabContent: some View {
        switch selectedTab {
        case 0: myGamesTab
        case 1: myTournamentsParticipationTab
        case 2: myCreatedTournamentsTab
        default: EmptyView()
        }
    }

    // MARK: - Управление сворачиваемыми секциями

    // Свёрнута ли секция с данным ключом
    private func isCollapsed(_ key: String) -> Bool {
        collapsedSections.contains(key)
    }

    // Переключить состояние секции с анимацией
    private func toggleSection(_ key: String) {
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
    private func loadDataForSection(_ key: String) {
        guard let userId = authService.currentUserId else { return }

        switch key {
        case "games_history":
            if !historyLoaded {
                sparringService.loadMyCompletedGames(userId: userId)
                historyLoaded = true
            }
        case "part_completed", "created_completed":
            if !completedTournamentsLoaded {
                loadCompletedTournaments(userId: userId)
                completedTournamentsLoaded = true
            }
        default:
            break
        }
    }

    // Завершённые турниры загружаются отдельно
    private func loadCompletedTournaments(userId: String) {
        let db = Firestore.firestore()
        db.collection("tournaments")
            .whereField("status", isEqualTo: "completed")
            .getDocuments { snapshot, _ in
                DispatchQueue.main.async {
                    guard let documents = snapshot?.documents else { return }

                    self.completedParticipationTournaments = documents.compactMap { doc in
                        let data = doc.data()
                        guard let participants = data["participants"] as? [String],
                              participants.contains(userId) else { return nil }
                        var result = data
                        result["documentId"] = doc.documentID
                        return result
                    }

                    self.completedCreatedTournaments = documents.compactMap { doc in
                        let data = doc.data()
                        guard data["organizerId"] as? String == userId else { return nil }
                        var result = data
                        result["documentId"] = doc.documentID
                        return result
                    }
                }
            }
    }

    // MARK: - Вкладка "Игры"
    // Приоритет: Идёт сейчас → Активные заявки → Предстоящие → История

    private var myGamesTab: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {

            // Делим забронированные игры на "идущие сейчас" и "предстоящие"
            let inProgressGames = sparringService.myBookedGames.filter {
                ($0["status"] as? String) == "in_progress"
            }
            let upcomingGames = sparringService.myBookedGames.filter {
                ($0["status"] as? String) != "in_progress"
            }

            // Секция 1: Идёт сейчас (приоритет сверху)
            if !inProgressGames.isEmpty {
                sectionHeader("Идёт сейчас", count: inProgressGames.count, key: "games_inProgress")
                if !isCollapsed("games_inProgress") {
                    VStack(spacing: AppSpacing.m) {
                        ForEach(inProgressGames.indices, id: \.self) { index in
                            gameCard(inProgressGames[index], status: "in_progress")
                        }
                    }
                }
            }

            // Секция 2: Активные заявки (мои опубликованные, ещё не забронированные)
            if !sparringService.myActiveRequests.isEmpty {
                sectionHeader("Активные заявки", count: sparringService.myActiveRequests.count, key: "games_active")
                if !isCollapsed("games_active") {
                    VStack(spacing: AppSpacing.m) {
                        ForEach(sparringService.myActiveRequests.indices, id: \.self) { index in
                            gameCard(sparringService.myActiveRequests[index], status: "active")
                        }
                    }
                }
            }

            // Секция 3: Предстоящие игры (забронированные, ещё не начавшиеся)
            if !upcomingGames.isEmpty {
                sectionHeader("Предстоящие игры", count: upcomingGames.count, key: "games_upcoming")
                if !isCollapsed("games_upcoming") {
                    VStack(spacing: AppSpacing.m) {
                        ForEach(upcomingGames.indices, id: \.self) { index in
                            let game = upcomingGames[index]
                            let realStatus = game["status"] as? String ?? "booked"
                            gameCard(game, status: realStatus)
                        }
                    }
                }
            }

            // Секция 4: История (завершённые и истёкшие)
            // Секция всегда показывается, чтобы пользователь мог её раскрыть
            sectionHeader("История", count: sparringService.completedGamesCount, key: "games_history")
            if !isCollapsed("games_history") {
                if sparringService.myCompletedGames.isEmpty {
                    Text("История игр пуста")
                        .font(.subheadline)
                        .foregroundColor(AppColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppSpacing.m)
                } else {
                    VStack(spacing: AppSpacing.m) {
                        ForEach(sparringService.myCompletedGames.indices, id: \.self) { index in
                            gameCard(sparringService.myCompletedGames[index], status: "completed")
                        }
                    }
                }
            }

            // Если совсем ничего нет — показываем пустое состояние
            if sparringService.myActiveRequests.isEmpty &&
                sparringService.myBookedGames.isEmpty &&
                sparringService.myCompletedGames.isEmpty {
                emptyState(
                    icon: "sportscourt",
                    title: "Пока нет игр",
                    subtitle: "Создайте первую заявку"
                )
            }
        }
    }

    // MARK: - Вкладка "Участвую"
    // Турниры, в которых я записан как игрок

    private var myTournamentsParticipationTab: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {

            // Все мои активные турниры (где я участник)
            let myTournaments = tournamentService.tournaments.filter {
                guard let participants = $0["participants"] as? [String],
                      let userId = authService.currentUserId else { return false }
                return participants.contains(userId)
            }

            let inProgressTournaments = myTournaments.filter {
                ($0["status"] as? String) == "in_progress"
            }
            let upcomingTournaments = myTournaments.filter {
                ($0["status"] as? String) != "in_progress"
            }

            // Если совсем нет — пустое состояние
            if myTournaments.isEmpty && completedParticipationTournaments.isEmpty {
                emptyState(
                    icon: "trophy",
                    title: "Вы не записаны на турниры",
                    subtitle: "Найдите интересный турнир и запишитесь"
                )
            } else {

                // Секция 1: Идёт сейчас
                if !inProgressTournaments.isEmpty {
                    sectionHeader("Идёт сейчас", count: inProgressTournaments.count, key: "part_inProgress")
                    if !isCollapsed("part_inProgress") {
                        VStack(spacing: AppSpacing.m) {
                            ForEach(inProgressTournaments.indices, id: \.self) { i in
                                NavigationLink {
                                    TournamentDetailView(
                                        tournament: inProgressTournaments[i],
                                        authService: authService,
                                        tournamentService: tournamentService
                                    )
                                } label: {
                                    tournamentCard(inProgressTournaments[i])
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Секция 2: Предстоящие
                if !upcomingTournaments.isEmpty {
                    sectionHeader("Предстоящие", count: upcomingTournaments.count, key: "part_upcoming")
                    if !isCollapsed("part_upcoming") {
                        VStack(spacing: AppSpacing.m) {
                            ForEach(upcomingTournaments.indices, id: \.self) { i in
                                NavigationLink {
                                    TournamentDetailView(
                                        tournament: upcomingTournaments[i],
                                        authService: authService,
                                        tournamentService: tournamentService
                                    )
                                } label: {
                                    tournamentCard(upcomingTournaments[i])
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Секция 3: Завершённые
                sectionHeader("Завершённые", count: completedParticipationCount, key: "part_completed")
                if !isCollapsed("part_completed") {
                    if completedParticipationTournaments.isEmpty {
                        Text("Завершённых турниров пока нет")
                            .font(.subheadline)
                            .foregroundColor(AppColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, AppSpacing.m)
                    } else {
                        VStack(spacing: AppSpacing.m) {
                            ForEach(completedParticipationTournaments.indices, id: \.self) { i in
                                NavigationLink {
                                    TournamentDetailView(
                                        tournament: completedParticipationTournaments[i],
                                        authService: authService,
                                        tournamentService: tournamentService
                                    )
                                } label: {
                                    tournamentCard(completedParticipationTournaments[i], isCompleted: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Вкладка "Создаю"
    // Турниры, которые я организую

    private var myCreatedTournamentsTab: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {

            // Все турниры где я организатор (кроме завершённых)
            let activeTournaments = tournamentService.tournaments.filter {
                $0["organizerId"] as? String == authService.currentUserId
            }

            let inProgressTournaments = activeTournaments.filter {
                ($0["status"] as? String) == "in_progress"
            }
            let upcomingTournaments = activeTournaments.filter {
                ($0["status"] as? String) != "in_progress"
            }

            if activeTournaments.isEmpty && completedCreatedTournaments.isEmpty {
                emptyState(
                    icon: "crown",
                    title: "Вы не создавали турниров",
                    subtitle: "Нажмите + чтобы создать первый"
                )
            } else {

                // Секция 1: Идёт сейчас
                if !inProgressTournaments.isEmpty {
                    sectionHeader("Идёт сейчас", count: inProgressTournaments.count, key: "created_inProgress")
                    if !isCollapsed("created_inProgress") {
                        VStack(spacing: AppSpacing.m) {
                            ForEach(inProgressTournaments.indices, id: \.self) { i in
                                NavigationLink {
                                    TournamentDetailView(
                                        tournament: inProgressTournaments[i],
                                        authService: authService,
                                        tournamentService: tournamentService
                                    )
                                } label: {
                                    tournamentCard(inProgressTournaments[i])
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Секция 2: Активные (предстоящие)
                if !upcomingTournaments.isEmpty {
                    sectionHeader("Активные", count: upcomingTournaments.count, key: "created_upcoming")
                    if !isCollapsed("created_upcoming") {
                        VStack(spacing: AppSpacing.m) {
                            ForEach(upcomingTournaments.indices, id: \.self) { i in
                                NavigationLink {
                                    TournamentDetailView(
                                        tournament: upcomingTournaments[i],
                                        authService: authService,
                                        tournamentService: tournamentService
                                    )
                                } label: {
                                    tournamentCard(upcomingTournaments[i])
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Секция 3: Завершённые
                sectionHeader("Завершённые", count: completedCreatedTournaments.count, key: "created_completed")
                if !isCollapsed("created_completed") {
                    if completedCreatedTournaments.isEmpty {
                        Text("Завершённых турниров пока нет")
                            .font(.subheadline)
                            .foregroundColor(AppColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, AppSpacing.m)
                    } else {
                        VStack(spacing: AppSpacing.m) {
                            ForEach(completedCreatedTournaments.indices, id: \.self) { i in
                                NavigationLink {
                                    TournamentDetailView(
                                        tournament: completedCreatedTournaments[i],
                                        authService: authService,
                                        tournamentService: tournamentService
                                    )
                                } label: {
                                    tournamentCard(completedCreatedTournaments[i], isCompleted: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Универсальные компоненты

    // Заголовок секции — кликабельный, со стрелкой и счётчиком
    private func sectionHeader(_ title: String, count: Int, key: String) -> some View {
        Button {
            toggleSection(key)
        } label: {
            HStack(spacing: AppSpacing.s) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColor.textPrimary)

                // Счётчик элементов в секции
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundColor(AppColor.textSecondary)
                    .padding(.horizontal, AppSpacing.s)
                    .padding(.vertical, 2)
                    .background(AppColor.cardBackground)
                    .cornerRadius(AppRadius.small)

                Spacer()

                // Стрелка: вниз = развёрнуто, влево = свёрнуто
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                    .foregroundColor(AppColor.textSecondary)
                    .rotationEffect(.degrees(isCollapsed(key) ? -90 : 0))
            }
        }
        .buttonStyle(.plain)
    }

    // Пустое состояние с иконкой и поясняющим текстом
    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: AppSpacing.m) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(AppColor.textTertiary)
            Text(title)
                .font(.headline)
                .foregroundColor(AppColor.textSecondary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(AppColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
    }

    // MARK: - Карточка игры (спарринга)
    // Кликабельная: active → редактирование, остальные → детали игры

    private func gameCard(_ game: [String: Any], status: String) -> some View {
        Button {
            if status == "active", let docId = game["documentId"] as? String {
                editingRequestId = docId
            } else if ["booked", "in_progress", "completed", "expired"].contains(status) {
                bookedGameData = game
                bookedGameId   = game["documentId"] as? String
            }
        } label: {
            VStack(spacing: 0) {

                // Шапка карточки: партнёр (если есть) + статус-бейдж
                HStack {
                    if let partnerName = game["partnerName"] as? String, !partnerName.isEmpty {
                        HStack(spacing: AppSpacing.s) {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(AppColor.primary)
                            Text(partnerName)
                                .font(.headline)
                                .foregroundColor(AppColor.textPrimary)
                        }
                    } else {
                        // Если партнёра ещё нет (активная заявка) — показываем кого ищем
                        Text("Ищу: \(game["desiredLevel"] as? String ?? "—")")
                            .font(.headline)
                            .foregroundColor(AppColor.textPrimary)
                    }

                    Spacer()
                    statusBadge(status)
                }
                .padding(AppSpacing.l)

                Divider()

                // Тело карточки: место + дата/время
                HStack(spacing: AppSpacing.l) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(AppColor.primary)
                                .font(.caption)
                            Text(game["city"] as? String ?? "")
                                .font(.subheadline.bold())
                                .foregroundColor(AppColor.textPrimary)
                        }
                        Text(game["location"] as? String ?? "")
                            .font(.caption)
                            .foregroundColor(AppColor.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                        if let timestamp = game["date"] as? Timestamp {
                            let f = DateFormatter()
                            let _ = (f.locale = Locale(identifier: "ru_RU"))
                            let _ = (f.dateFormat = "d MMM")
                            Text(f.string(from: timestamp.dateValue()))
                                .font(.subheadline.bold())
                                .foregroundColor(AppColor.textPrimary)
                        }
                        Text(game["timeSlot"] as? String ?? "")
                            .font(.caption)
                            .foregroundColor(AppColor.textSecondary)
                    }
                }
                .padding(AppSpacing.l)
            }
            .background(AppColor.cardBackground)
            .cornerRadius(AppRadius.large)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Карточка турнира

    private func tournamentCard(_ tournament: [String: Any], isCompleted: Bool = false) -> some View {
        VStack(spacing: 0) {

            // Шапка: название + бейдж "Завершён" если применимо
            HStack {
                Text(tournament["title"] as? String ?? "")
                    .font(.headline)
                    .foregroundColor(AppColor.textPrimary)
                    .lineLimit(2)
                Spacer()
                if isCompleted {
                    Text("Завершён")
                        .font(.caption.bold())
                        .foregroundColor(AppColor.textSecondary)
                        .padding(.horizontal, AppSpacing.s)
                        .padding(.vertical, 4)
                        .background(AppColor.background)
                        .cornerRadius(AppRadius.small)
                }
            }
            .padding(AppSpacing.l)

            Divider()

            // Тело: место + дата/время
            HStack(spacing: AppSpacing.l) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(AppColor.primary)
                            .font(.caption)
                        Text(tournament["city"] as? String ?? "")
                            .font(.subheadline.bold())
                            .foregroundColor(AppColor.textPrimary)
                    }
                    Text(tournament["location"] as? String ?? "")
                        .font(.caption)
                        .foregroundColor(AppColor.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    if let timestamp = tournament["date"] as? Timestamp {
                        let f = DateFormatter()
                        let _ = (f.locale = Locale(identifier: "ru_RU"))
                        let _ = (f.dateFormat = "d MMM")
                        Text(f.string(from: timestamp.dateValue()))
                            .font(.subheadline.bold())
                            .foregroundColor(AppColor.textPrimary)
                    }
                    if let startTime = tournament["startTime"] as? String, !startTime.isEmpty {
                        Text(startTime)
                            .font(.caption)
                            .foregroundColor(AppColor.textSecondary)
                    }
                }
            }
            .padding(AppSpacing.l)

            Divider()

            // Подвал: счётчик участников
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.caption)
                    .foregroundColor(AppColor.textSecondary)
                let count = (tournament["participants"] as? [String])?.count ?? 0
                let max   = tournament["maxParticipants"] as? Int ?? 0
                Text("\(count) из \(max) участников")
                    .font(.caption)
                    .foregroundColor(AppColor.textSecondary)
                Spacer()
            }
            .padding(AppSpacing.l)
        }
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.large)
    }

    // MARK: - Бейдж статуса игры

    private func statusBadge(_ status: String) -> some View {
        Text(statusText(status))
            .font(.caption.bold())
            .foregroundColor(statusColor(status))
            .padding(.horizontal, AppSpacing.s)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.12))
            .cornerRadius(AppRadius.small)
    }

    // Перевод статуса на русский
    private func statusText(_ status: String) -> String {
        switch status {
        case "active":      return "Активна"
        case "booked":      return "Забронирована"
        case "in_progress": return "Идёт"
        case "completed":   return "Завершена"
        case "expired":     return "Истекла"
        default:            return status
        }
    }

    // Цвет статуса по смыслу: зелёный=активная, синий=инфо, оранжевый=внимание, красный=ошибка
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active":      return AppColor.primary
        case "booked":      return AppColor.info
        case "in_progress": return AppColor.warning
        case "completed":   return AppColor.textSecondary
        case "expired":     return AppColor.danger
        default:            return AppColor.textSecondary
        }
    }

    // MARK: - Загрузка данных

    // Главная функция загрузки — вызывается при .onAppear и после редактирований
    private func loadAllData() {
        guard let userId = authService.currentUserId else { return }

        // Сначала проверяем статусы (вдруг что-то завершилось пока приложение было закрыто)
        StatusManager.shared.checkAllStatuses()
        
        // Обновляем счётчик уведомлений
            NotificationService.shared.refreshUnreadCount(userId: userId)

        // Загружаем данные текущего пользователя
        Firestore.firestore().collection("users").document(userId).getDocument { doc, _ in
            DispatchQueue.main.async {
                isLoadingProfile = false
                userData = doc?.data() ?? [:]
            }
        }

        // Загружаем активные заявки и предстоящие игры
        sparringService.loadAll(userId: userId)
        
        sparringService.loadCompletedGamesCount(userId: userId)

        // Загружаем активные турниры (upcoming + in_progress)
        tournamentService.loadTournaments()
        
        loadCompletedTournamentsCount(userId: userId)

        // Завершённые турниры и история игр НЕ загружаются здесь —
        // они подгружаются только когда пользователь раскрывает соответствующую секцию
        // (см. loadDataForSection)
        
        // Загружаем рейтинг и количество отзывов
            ReviewService().loadRatingStats(forUserId: userId) { avg, count in
                self.averageRating = avg
                self.reviewsCount = count
            }
            
            // Считаем все турниры пользователя
            loadTournamentsCount(userId: userId)
        
    }
    
    private func loadTournamentsCount(userId: String) {
        let db = Firestore.firestore()
        
        db.collection("tournaments")
            .getDocuments { snapshot, _ in
                guard let documents = snapshot?.documents else { return }
                
                let count = documents.filter { doc in
                    let data = doc.data()
                    let isParticipant = (data["participants"] as? [String])?.contains(userId) ?? false
                    let isOrganizer = data["organizerId"] as? String == userId
                    return isParticipant || isOrganizer
                }.count
                
                DispatchQueue.main.async {
                    self.tournamentsCount = count
                }
            }
    }
    
    private func loadCompletedTournamentsCount(userId: String) {
        let db = Firestore.firestore()
        db.collection("tournaments")
            .whereField("status", isEqualTo: "completed")
            .count
            .getAggregation(source: .server) { snapshot, _ in
                // Здесь нельзя точно посчитать без загрузки — нужны участники
                // Загружаем только ID и participants для подсчёта
                db.collection("tournaments")
                    .whereField("status", isEqualTo: "completed")
                    .getDocuments { snapshot, _ in
                        DispatchQueue.main.async {
                            guard let documents = snapshot?.documents else { return }
                            completedParticipationCount = documents.filter {
                                ($0.data()["participants"] as? [String])?.contains(userId) ?? false
                            }.count
                            completedCreatedCount = documents.filter {
                                $0.data()["organizerId"] as? String == userId
                            }.count
                        }
                    }
            }
    }

    // MARK: - Вспомогательная структура
    // Нужна для sheet(item:) — он требует Identifiable, а String им не является

    struct IdentifiableString: Identifiable {
        let id: String
    }
}
