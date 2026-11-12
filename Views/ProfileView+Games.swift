import SwiftUI
import FirebaseFirestore

// MARK: - ProfileView: вкладка «Игры»

extension ProfileView {
    // MARK: - Вкладка "Игры"
    // Приоритет: Идёт сейчас → Активные заявки → Предстоящие → История

    var myGamesTab: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {

            // Совсем ничего нет: вместо пустых разделов — одно объяснение и кнопка «Найти игру»
            let nothingYet = sparringService.myActiveRequests.isEmpty &&
                sparringService.myBookedGames.isEmpty &&
                sparringService.myCompletedGames.isEmpty &&
                sparringService.completedGamesCount == 0

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
            // Секция показывается, как только есть что показывать, чтобы пользователь мог её раскрыть
            if !nothingYet {
                sectionHeader("История", count: sparringService.completedGamesCount, key: "games_history")
                if !isCollapsed("games_history") {
                    historyContent
                }
            }

            if nothingYet {
                emptyState(
                    icon: "figure.table.tennis",
                    title: "Пока нет игр",
                    subtitle: "Запишитесь на заявку другого игрока в ленте или создайте свою кнопкой «+».",
                    actionTitle: "Найти игру",
                    action: { appState.selectedTab = .feed }
                )
            }
        }
    }

    // MARK: - История: фильтры, месяцы, ленивый список

    /// Завершённые игры в виде, удобном для фильтров. Результат берётся из подтверждённых матчей.
    func historyGames(from source: [[String: Any]], myId: String) -> [HistoryGame] {
        source.compactMap { raw in
            guard let id = raw["documentId"] as? String else { return nil }
            let date = (raw["date"] as? Timestamp)?.dateValue()
                ?? (raw["createdAt"] as? Timestamp)?.dateValue()
                ?? Date(timeIntervalSince1970: 0)
            let record = matchesStore.meetingMatches(forRequest: id).record(for: myId)
            return HistoryGame(
                id: id,
                date: date,
                role: (raw["userId"] as? String) == myId ? .author : .partner,
                partnerId: raw["partnerId"] as? String ?? "",
                partnerName: raw["partnerName"] as? String ?? "",
                city: raw["city"] as? String ?? "",
                place: raw["location"] as? String ?? "",
                wasHeld: (raw["status"] as? String) != "expired",
                matchesWon: record.won,
                matchesLost: record.lost
            )
        }
    }

    @ViewBuilder
    var historyContent: some View {
        let source = sparringService.myCompletedGames

        if source.isEmpty {
            Text(historyLoaded ? "История игр пуста" : "Загружаем историю…")
                .font(.subheadline)
                .foregroundColor(AppColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, AppSpacing.m)
        } else {
            let all = historyGames(from: source, myId: authService.currentUserId ?? "")
            let shown = historyFilter.apply(to: all)

            VStack(alignment: .leading, spacing: AppSpacing.m) {
                if all.count >= FilterThreshold.games {
                    GameHistoryFilterBar(filter: $historyFilter, games: all, shownCount: shown.count)
                }

                if shown.isEmpty {
                    FilterEmptyResult { withAnimation { historyFilter.reset() } }
                } else {
                    historyList(shown, source: source)
                }
            }
        }
    }

    /// Ленивый список: карточки создаются только для видимых строк, даже если игр сотни
    private func historyList(_ games: [HistoryGame], source: [[String: Any]]) -> some View {
        var byId: [String: [String: Any]] = [:]
        for raw in source {
            if let id = raw["documentId"] as? String { byId[id] = raw }
        }

        return LazyVStack(spacing: AppSpacing.m) {
            if historyFilter.sort.isByDate {
                ForEach(HistoryBuckets.groupedByMonth(games, date: { $0.date })) { group in
                    HistoryMonthHeader(month: group.month, count: group.items.count)
                    ForEach(group.items) { item in
                        historyCard(item, byId: byId)
                    }
                }
            } else {
                ForEach(games) { item in
                    historyCard(item, byId: byId)
                }
            }
        }
    }

    @ViewBuilder
    private func historyCard(_ item: HistoryGame, byId: [String: [String: Any]]) -> some View {
        if let raw = byId[item.id] {
            gameCard(raw, status: raw["status"] as? String ?? "completed")
        }
    }

    // MARK: - Карточка игры (спарринга)
    // Кликабельная: active → редактирование, остальные → детали игры

    func gameCard(_ game: [String: Any], status: String) -> some View {
        VStack(spacing: 0) {
            gameCardBody(game, status: status)

            // Нужно действие со счётом — отдельная заметная полоса, нажатие ведёт сразу к вводу счёта
            if let action = matchAction(for: game) {
                Divider()
                Button {
                    bookedGameOpensMatch = true
                    bookedGameData = game
                    bookedGameId   = game["documentId"] as? String
                } label: {
                    HStack(spacing: AppSpacing.s) {
                        Image(systemName: "list.clipboard")
                        Text(action)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(AppColor.primary)
                    .padding(.horizontal, AppSpacing.l)
                    .frame(minHeight: 44)
                    .background(AppColor.primary.opacity(0.10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }

    private func gameCardBody(_ game: [String: Any], status: String) -> some View {
        Button {
            if status == "active", let docId = game["documentId"] as? String {
                editingRequestId = docId
            } else if ["booked", "in_progress", "completed", "expired"].contains(status) {
                bookedGameOpensMatch = false
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
                    matchChip(for: game)
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
                            Text(CityName.canonical(game["city"] as? String ?? ""))
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
                            Text(AppDate.dayShort(timestamp.dateValue()))
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
