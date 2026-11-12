import SwiftUI
import FirebaseFirestore

// MARK: - ProfileView: вкладки «Участвую» и «Организую»

extension ProfileView {
    // MARK: - Вкладка "Участвую"
    // Турниры, в которых я записан как игрок

    var myTournamentsParticipationTab: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {

            // Все мои активные турниры (где я участник)
            let myTournaments = activeParticipationTournaments

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
                    subtitle: "Найдите интересный турнир и запишитесь",
                    actionTitle: "Смотреть турниры",
                    action: { appState.selectedTab = .tournaments }
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

    // MARK: - Вкладка "Организую"
    // Турниры, которые я организую

    var myCreatedTournamentsTab: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {

            // Все турниры где я организатор (кроме завершённых)
            let activeTournaments = activeCreatedTournaments

            let inProgressTournaments = activeTournaments.filter {
                ($0["status"] as? String) == "in_progress"
            }
            let upcomingTournaments = activeTournaments.filter {
                ($0["status"] as? String) != "in_progress"
            }

            if activeTournaments.isEmpty && completedCreatedTournaments.isEmpty {
                emptyState(
                    icon: "crown",
                    title: "Вы пока не организовывали турниров",
                    subtitle: "Нажмите + и выберите «Турнир»"
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
        ProfileTournamentCard(tournament: tournament, isCompleted: isCompleted)
    }
}
