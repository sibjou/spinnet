import SwiftUI
import FirebaseFirestore

// MARK: - PlayerProfileView
// Страница игрока — такая же, как его собственный профиль, только для просмотра:
// те же шапка, переключатель вкладок и карточки. Что именно видно, решает сам игрок
// (Настройки → Приватность). Открывается отовсюду, где показано имя или аватар игрока.
struct PlayerProfileView: View {
    let userId: String

    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var appState: AppState
    @StateObject private var matchesStore = PlayerMatchesStore()
    @StateObject private var tournamentService = TournamentService()

    // Данные игрока
    @State private var userData: [String: Any] = [:]
    @State private var privacy = PrivacySettings()
    @State private var isLoading = true
    @State private var gamesCount = 0
    @State private var averageRating: Double = 0
    @State private var reviewsCount = 0
    @State private var participating: [[String: Any]] = []
    @State private var organizing: [[String: Any]] = []
    @State private var headToHeadWithMe: HeadToHead?

    // Экран
    @State private var selectedTab = 0
    @State private var showReviews = false

    // Блокировка
    @State private var isBlockedByMe = false      // я заблокировал его
    @State private var isBlockedByThem = false    // он заблокировал меня
    @State private var showBlockConfirm = false
    @State private var isProcessingBlock = false

    private var currentUserId: String { authService.currentUserId ?? "" }
    private var isMyProfile: Bool { userId == currentUserId }

    /// Профиль недоступен, если кто-то кого-то заблокировал
    private var isUnavailable: Bool { isBlockedByMe || isBlockedByThem }

    private var fullName: String { UserService.fullName(from: userData) }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding(.top, 50)
            } else if isUnavailable {
                unavailableState
            } else {
                profileContent
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColor.background)
        .connectionNotice()
        .navigationTitle(fullName.isEmpty ? "Профиль" : fullName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Блокировка — только для чужого профиля и если он не заблокировал меня
            if !isMyProfile && !isBlockedByThem {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if isBlockedByMe {
                            Button {
                                unblockUser()
                            } label: {
                                Label("Разблокировать", systemImage: "person.crop.circle.badge.checkmark")
                            }
                        } else {
                            Button(role: .destructive) {
                                showBlockConfirm = true
                            } label: {
                                Label("Заблокировать", systemImage: "person.crop.circle.badge.xmark")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Заблокировать игрока?", isPresented: $showBlockConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Заблокировать", role: .destructive) { blockUser() }
        } message: {
            Text("Вы больше не увидите друг друга в ленте. Все забронированные игры между вами будут отменены.")
        }
        .sheet(isPresented: $showReviews) {
            NavigationStack {
                ReviewsListView(userId: userId, userName: fullName)
            }
        }
        .onAppear { loadPlayerData() }
    }

    // MARK: - Контент профиля

    private var profileContent: some View {
        VStack(spacing: AppSpacing.l) {

            if isMyProfile {
                ownProfileNotice
            }

            ProfileHeaderView(
                userId: userId,
                firstName: userData["firstName"] as? String ?? "",
                lastName: userData["lastName"] as? String ?? "",
                city: userData["city"] as? String ?? "",
                skillLevel: userData["skillLevel"] as? String ?? "",
                grip: userData["grip"] as? String ?? "",
                playStyle: userData["playStyle"] as? String ?? "",
                gamesCount: privacy.canView(.stats, isOwner: isMyProfile) ? gamesCount : nil,
                tournamentsCount: privacy.canView(.tournaments, isOwner: isMyProfile) ? tournamentIds.count : nil,
                ttwRating: userData["ttwRating"] as? Int ?? 0,
                averageRating: averageRating,
                reviewsCount: reviewsCount,
                onTapReviews: { showReviews = true }
            )

            if let h2h = headToHeadWithMe {
                headToHeadCard(h2h)
                    .padding(.horizontal, AppSpacing.l)
            }

            if let link = ratingURL {
                Link(destination: link) {
                    Label("Профиль на r.ttw.ru", systemImage: "link")
                        .font(.subheadline)
                }
            }

            ProfileTabBar(
                items: [
                    .init(id: 0, title: "Статистика", icon: "chart.bar.xaxis"),
                    .init(id: 1, title: "Матчи",      icon: "list.clipboard"),
                    .init(id: 2, title: "Турниры",    icon: "trophy.fill")
                ],
                selection: $selectedTab
            )
            .padding(.horizontal, AppSpacing.l)

            tabContent
                .padding(.horizontal, AppSpacing.l)
        }
        .padding(.vertical, AppSpacing.l)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            StatsDashboardView(
                store: matchesStore,
                userId: userId,
                isOwner: isMyProfile,
                privacy: privacy,
                viewerPlan: authService.userProfile?.plan ?? .free
            )
        case 1:
            if privacy.canView(.matchHistory, isOwner: isMyProfile) {
                MatchHistoryList(store: matchesStore, userId: userId)
            } else {
                ProfilePlaceholder(
                    icon: "lock.fill",
                    title: "Матчи скрыты",
                    subtitle: "Игрок не показывает список матчей"
                )
            }
        default:
            tournamentsTab
        }
    }

    // MARK: - Вкладка «Турниры»

    private var tournamentIds: Set<String> {
        Set((participating + organizing).compactMap { $0["documentId"] as? String })
    }

    @ViewBuilder
    private var tournamentsTab: some View {
        if !privacy.canView(.tournaments, isOwner: isMyProfile) {
            ProfilePlaceholder(
                icon: "lock.fill",
                title: "Турниры скрыты",
                subtitle: "Игрок не показывает свои турниры"
            )
        } else if participating.isEmpty && organizing.isEmpty {
            ProfilePlaceholder(
                icon: "trophy",
                title: "Пока нет турниров",
                subtitle: "Здесь появятся турниры, в которых игрок участвует или которые организует"
            )
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                tournamentSection("Организует", items: organizing)
                tournamentSection("Участвует", items: participating)
            }
        }
    }

    @ViewBuilder
    private func tournamentSection(_ title: String, items: [[String: Any]]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                HStack(spacing: AppSpacing.s) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(AppColor.textPrimary)
                    Text("\(items.count)")
                        .font(.caption.bold())
                        .foregroundColor(AppColor.textSecondary)
                        .padding(.horizontal, AppSpacing.s)
                        .padding(.vertical, 2)
                        .background(AppColor.cardBackground)
                        .cornerRadius(AppRadius.small)
                }
                ForEach(items.indices, id: \.self) { index in
                    NavigationLink {
                        TournamentDetailView(
                            tournament: items[index],
                            authService: authService,
                            tournamentService: tournamentService
                        )
                    } label: {
                        ProfileTournamentCard(
                            tournament: items[index],
                            isCompleted: (items[index]["status"] as? String) == "completed"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - «Это ваш профиль»
    // Сюда можно попасть по своему имени из чужого профиля, отзыва или списка соперников.
    // Чтобы не путаться, подписываем страницу и даём короткий путь на вкладку «Профиль».

    private var ownProfileNotice: some View {
        HStack(spacing: AppSpacing.m) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title2)
                .foregroundColor(AppColor.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Это ваш профиль")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColor.textPrimary)
                Text("Здесь вы видите всё, остальным показано только разрешённое в приватности")
                    .font(.caption)
                    .foregroundColor(AppColor.textSecondary)
            }
            Spacer(minLength: AppSpacing.s)
            Button("Мой профиль") {
                appState.openOwnProfile()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(AppSpacing.l)
        .frame(maxWidth: .infinity)
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.medium)
        .padding(.horizontal, AppSpacing.l)
    }

    // MARK: - «Личные встречи»

    private func headToHeadCard(_ h2h: HeadToHead) -> some View {
        HStack(spacing: AppSpacing.m) {
            Image(systemName: "person.2.fill")
                .foregroundColor(AppColor.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Личные встречи")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColor.textPrimary)
                Text("\(h2h.matches) \(StatsDashboardView.matchesWord(h2h.matches)): вы выиграли \(h2h.wins), соперник — \(h2h.losses)")
                    .font(.caption)
                    .foregroundColor(AppColor.textSecondary)
            }
            Spacer()
        }
        .padding(AppSpacing.l)
        .frame(maxWidth: .infinity)
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.medium)
    }

    private var ratingURL: URL? {
        guard let text = userData["ratingLink"] as? String, !text.isEmpty,
              let url = URL(string: text), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    // MARK: - Экран «Пользователь недоступен»

    private var unavailableState: some View {
        // Разблокировка — только если это я заблокировал
        EmptyStateView(
            art: .symbol("person.crop.circle.badge.xmark"),
            title: "Пользователь недоступен",
            message: isBlockedByMe ? "Вы заблокировали этого игрока" : "Профиль недоступен",
            primaryTitle: isBlockedByMe ? "Разблокировать" : nil,
            primaryAction: isBlockedByMe ? { if !isProcessingBlock { unblockUser() } } : nil
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Загрузка данных игрока

    private func loadPlayerData() {
        // Сначала проверяем блокировки
        BlockService.shared.loadBlocks {
            self.isBlockedByMe   = BlockService.shared.blockedUserIds.contains(self.userId)
            self.isBlockedByThem = BlockService.shared.blockedByUserIds.contains(self.userId)

            // Если недоступен — не грузим данные профиля
            if self.isUnavailable {
                self.isLoading = false
                return
            }

            self.fetchProfileData()
        }
    }

    private func fetchProfileData() {
        UserService.shared.fetchUser(id: userId) { data in
            self.userData = data ?? [:]
            self.privacy = PrivacySettings(userData: data)
            self.isLoading = false
            self.loadAllowedSections()
        }
    }

    /// Грузим только то, что игрок разрешил показывать
    private func loadAllowedSections() {
        if privacy.canView(.stats, isOwner: isMyProfile) {
            matchesStore.load(userId: userId, force: true)
            SparringService().countCompletedGames(userId: userId) { count in
                self.gamesCount = count
            }
        }

        if privacy.canView(.tournaments, isOwner: isMyProfile) {
            tournamentService.loadUserTournaments(userId: userId) { participating, organizing in
                self.participating = participating
                self.organizing = organizing
            }
        }

        ReviewService().loadRatingStats(forUserId: userId) { average, count in
            self.averageRating = average
            self.reviewsCount = count
        }

        // «Ваши встречи» считаем по моим матчам — это мои данные, приватность соперника не затрагивается
        if !isMyProfile, !currentUserId.isEmpty {
            MatchService.shared.fetchMatches(userId: currentUserId) { matches in
                self.headToHeadWithMe = StatsCalculator.headToHead(
                    matches: matches, userId: self.currentUserId, opponentId: self.userId
                )
            }
        }
    }

    // MARK: - Блокировка / Разблокировка

    private func blockUser() {
        isProcessingBlock = true
        BlockService.shared.block(userId: userId) { success in
            isProcessingBlock = false
            if success {
                isBlockedByMe = true
            }
        }
    }

    private func unblockUser() {
        isProcessingBlock = true
        BlockService.shared.unblock(userId: userId) { success in
            isProcessingBlock = false
            if success {
                isBlockedByMe = false
                // Перезагружаем данные профиля после разблокировки
                isLoading = true
                fetchProfileData()
            }
        }
    }
}
