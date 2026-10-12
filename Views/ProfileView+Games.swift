import SwiftUI
import FirebaseFirestore

// MARK: - ProfileView: вкладка «Игры»

extension ProfileView {
    // MARK: - Вкладка "Игры"
    // Приоритет: Идёт сейчас → Активные заявки → Предстоящие → История

    var myGamesTab: some View {
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

    // MARK: - Карточка игры (спарринга)
    // Кликабельная: active → редактирование, остальные → детали игры

    func gameCard(_ game: [String: Any], status: String) -> some View {
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
                            InitialsAvatar(
                                fullName: partnerName,
                                userId: game["partnerId"] as? String ?? "",
                                size: AppSize.avatarSmall
                            )
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
}
