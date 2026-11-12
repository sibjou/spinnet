import SwiftUI
import FirebaseFirestore

struct TournamentListView: View {
    @ObservedObject var authService: AuthService
    @StateObject private var tournamentService = TournamentService()
    @StateObject private var viewModel = TournamentViewModel()

    @State private var showCreateTournament = false
    @State private var showCityPicker = false
    @EnvironmentObject private var appState: AppState
    // Вкладка остаётся в памяти; свежий список подгружается, если с прошлой загрузки прошло больше минуты
    @State private var loadPolicy = RefreshPolicy(minInterval: 60)

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.hasLoadedOnce && viewModel.displayedTournaments.isEmpty {
                    RefreshableState { LoadingStateView(title: "Загружаем турниры…") }
                } else if viewModel.displayedTournaments.isEmpty {
                    // В обёртке, чтобы пустой экран тоже можно было потянуть вниз
                    RefreshableState { emptyState }
                } else {
                    tournamentList
                }
            }
            .tabBarInset()
            .navigationTitle("Турниры")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showCreateTournament) {
                CreateTournamentView(
                    authService: authService,
                    tournamentService: tournamentService,
                    isPresented: $showCreateTournament
                )
            }
            .sheet(isPresented: $showCityPicker) {
                CityPickerView(selectedCity: $viewModel.filterCity, isPresented: $showCityPicker, allCitiesTitle: "Все города")
            }
            .task {
                if loadPolicy.shouldRun() { viewModel.loadFromServer() }
            }
            .onChange(of: appState.selectedTab) { _, tab in
                if tab == .tournaments, loadPolicy.shouldRun() { viewModel.loadFromServer() }
            }
            .refreshable { await viewModel.refresh() }
            // Записались, отменили запись, завершили турнир на его странице — в списке счётчики должны обновиться
            .onChange(of: tournamentService.changeCounter) { _, _ in
                if loadPolicy.shouldRun(force: true) { viewModel.loadFromServer() }
            }
            // После создания турнира — перезагружаем
            .onChange(of: showCreateTournament) { _, isShowing in
                if !isShowing, loadPolicy.shouldRun(force: true) { viewModel.loadFromServer() }
            }
        }
    }

    // MARK: - Список

    private var tournamentList: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.m) {
                ForEach(viewModel.displayedTournaments) { item in
                    NavigationLink {
                        TournamentDetailView(
                            tournament: item.data,
                            authService: authService,
                            tournamentService: tournamentService
                        )
                    } label: {
                        TournamentCardView(
                            tournament: item.data,
                            currentUserId: authService.currentUserId
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppSpacing.l)
        }
    }

    // MARK: - Пустое состояние

    private var emptyState: some View {
        Group {
            if viewModel.hasActiveFilters {
                EmptyStateView(
                    art: .symbol("trophy"),
                    title: "Нет турниров по выбранным фильтрам",
                    message: "Попробуйте другой город или снимите фильтры",
                    primaryTitle: "Сбросить фильтры",
                    primaryAction: { viewModel.resetFilters() }
                )
            } else {
                EmptyStateView(
                    art: .symbol("trophy"),
                    title: "Пока нет турниров",
                    message: "Станьте первым: соберите игроков вашего города на турнир",
                    primaryTitle: "Создать турнир",
                    primaryAction: { showCreateTournament = true }
                )
            }
        }
    }

    // MARK: - Тулбар

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {  // ← изменили
            Menu {
                Button("Город: \(viewModel.filterCity)") {
                    showCityPicker = true
                }

                Toggle(isOn: $viewModel.filterOnlyFree) {
                    Label("Только со свободными местами", systemImage: "person.badge.plus")
                }

                if viewModel.hasActiveFilters {
                    Divider()
                    Button("Сбросить фильтры", role: .destructive) {
                        viewModel.resetFilters()
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(viewModel.hasActiveFilters ? AppColor.primary : .primary)
            }
        }
    }
    // MARK: - TournamentCardView
    struct TournamentCardView: View {
        let tournament: [String: Any]
        let currentUserId: String?

        var formattedDate: String {
            guard let timestamp = tournament["date"] as? Timestamp else { return "" }
            return AppDate.dayShort(timestamp.dateValue())
        }

        var participantCount: Int { (tournament["participants"] as? [String])?.count ?? 0 }
        var maxParticipants:  Int { tournament["maxParticipants"] as? Int ?? 0 }

        var isJoined: Bool {
            guard let userId = currentUserId,
                  let participants = tournament["participants"] as? [String] else { return false }
            return participants.contains(userId)
        }

        var isFull: Bool { participantCount >= maxParticipants && maxParticipants > 0 }

        var body: some View {
            VStack(spacing: 0) {

                // MARK: - Зона 1: Название + статус
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(tournament["title"] as? String ?? "")
                            .font(.headline)
                            .foregroundColor(AppColor.textPrimary)
                            .lineLimit(2)

                        Text(tournament["organizerName"] as? String ?? "Организатор")
                            .font(.caption)
                            .foregroundColor(AppColor.textSecondary)
                    }

                    Spacer()

                    statusBadge
                }
                .padding(AppSpacing.l)

                Divider()

                // MARK: - Зона 2: Город · Дата · Время
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
                        Text(formattedDate)
                            .font(.subheadline.bold())
                            .foregroundColor(AppColor.textPrimary)
                        if let startTime = tournament["startTime"] as? String, !startTime.isEmpty {
                            Text(startTime)
                                .font(.caption)
                                .foregroundColor(AppColor.textSecondary)
                        }
                    }
                }
                .padding(AppSpacing.l)

                Divider()

                // MARK: - Зона 3: Участники + прогресс
                HStack(spacing: AppSpacing.m) {
                    Image(systemName: "person.3.fill")
                        .foregroundColor(AppColor.textSecondary)
                        .font(.caption)

                    Text("\(participantCount) из \(maxParticipants)")
                        .font(.caption.bold())
                        .foregroundColor(AppColor.textPrimary)

                    // Прогресс-бар
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AppColor.cardBackground)
                            Capsule()
                                .fill(progressColor)
                                .frame(width: geo.size.width * progressRatio)
                        }
                    }
                    .frame(height: 6)

                    if isJoined {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                            Text("Вы")
                                .font(.caption.bold())
                        }
                        .foregroundColor(AppColor.primary)
                    }
                }
                .padding(AppSpacing.l)
            }
            .background(AppColor.cardBackground)
            .cornerRadius(AppRadius.large)
        }

        // MARK: - Статус-бейдж
        @ViewBuilder
        private var statusBadge: some View {
            // Красный — для ошибок. «Мест нет» — обычное состояние, поэтому спокойный серый
            if let status = tournament["status"] as? String, status == "in_progress" {
                badge(text: "Идёт", color: AppColor.warning)
            } else if isFull {
                badge(text: "Мест нет", color: Color(.systemGray2))
            } else {
                badge(text: "Открыт", color: AppColor.success)
            }
        }

        /// Цветная точка и текст обычным цветом: статус читается и без различения оттенков
        private func badge(text: String, color: Color) -> some View {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(text)
                    .font(.caption.bold())
                    .foregroundColor(AppColor.textPrimary)
            }
            .padding(.horizontal, AppSpacing.s + 2)
            .padding(.vertical, 5)
            .background(Color(.systemBackground))
            .clipShape(Capsule())
        }

        private var progressRatio: CGFloat {
            guard maxParticipants > 0 else { return 0 }
            return min(CGFloat(participantCount) / CGFloat(maxParticipants), 1.0)
        }

        private var progressColor: Color {
            if progressRatio >= 1.0 { return Color(.systemGray2) }
            if progressRatio >= 0.75 { return AppColor.warning }
            return AppColor.primary
        }
    }
}
