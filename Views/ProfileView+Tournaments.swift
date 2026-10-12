import SwiftUI
import FirebaseFirestore

// MARK: - ProfileView: вкладки «Участвую» и «Создаю»

extension ProfileView {
    // MARK: - Вкладка "Участвую"
    // Турниры, в которых я записан как игрок

    var myTournamentsParticipationTab: some View {
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

    var myCreatedTournamentsTab: some View {
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

    // MARK: - Карточка турнира

    func tournamentCard(_ tournament: [String: Any], isCompleted: Bool = false) -> some View {
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
}
