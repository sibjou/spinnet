import SwiftUI
import FirebaseFirestore

struct TournamentListView: View {
    @ObservedObject var authService: AuthService
    @StateObject private var tournamentService = TournamentService()
    @StateObject private var viewModel = TournamentViewModel()

    @State private var showCreateTournament = false
    @State private var showCityPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.displayedTournaments.isEmpty {
                    ProgressView("Загрузка турниров...")
                } else if viewModel.displayedTournaments.isEmpty {
                    emptyState
                } else {
                    tournamentList
                }
            }
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
                CityPickerView(selectedCity: $viewModel.filterCity, isPresented: $showCityPicker)
            }
            .task { viewModel.loadFromServer() }
            .refreshable { viewModel.loadFromServer() }
            // После создания турнира — перезагружаем
            .onChange(of: showCreateTournament) { _, isShowing in
                if !isShowing { viewModel.loadFromServer() }
            }
        }
    }

    // MARK: - Список

    private var tournamentList: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.m) {
                ForEach(viewModel.displayedTournaments.indices, id: \.self) { index in
                    let tournament = viewModel.displayedTournaments[index]
                    NavigationLink {
                        TournamentDetailView(
                            tournament: tournament,
                            authService: authService,
                            tournamentService: tournamentService
                        )
                    } label: {
                        TournamentCardView(
                            tournament: tournament,
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
        VStack(spacing: 12) {
            Image(systemName: "trophy")
                .font(.system(size: 50))
                .foregroundColor(.gray)

            if viewModel.hasActiveFilters {
                Text("Нет турниров по выбранным фильтрам")
                    .foregroundColor(.secondary)
                Button("Сбросить фильтры") { viewModel.resetFilters() }
                    .foregroundColor(.green)
            } else {
                Text("Пока нет турниров")
                    .foregroundColor(.secondary)
                Text("Создайте первый!")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                    .foregroundColor(viewModel.hasActiveFilters ? .green : .primary)
            }
        }
    }
    // MARK: - TournamentCardView
    struct TournamentCardView: View {
        let tournament: [String: Any]
        let currentUserId: String?

        var formattedDate: String {
            guard let timestamp = tournament["date"] as? Timestamp else { return "" }
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateFormat = "d MMM"
            return f.string(from: timestamp.dateValue())
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
            if let status = tournament["status"] as? String, status == "in_progress" {
                badge(text: "Идёт", color: AppColor.warning)
            } else if isFull {
                badge(text: "Мест нет", color: AppColor.danger)
            } else {
                badge(text: "Открыт", color: AppColor.primary)
            }
        }

        private func badge(text: String, color: Color) -> some View {
            Text(text)
                .font(.caption.bold())
                .foregroundColor(color)
                .padding(.horizontal, AppSpacing.s)
                .padding(.vertical, 4)
                .background(color.opacity(0.12))
                .cornerRadius(AppRadius.small)
        }

        private var progressRatio: CGFloat {
            guard maxParticipants > 0 else { return 0 }
            return min(CGFloat(participantCount) / CGFloat(maxParticipants), 1.0)
        }

        private var progressColor: Color {
            if progressRatio >= 1.0 { return AppColor.danger }
            if progressRatio >= 0.75 { return AppColor.warning }
            return AppColor.primary
        }
    }
}
