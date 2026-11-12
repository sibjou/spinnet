import SwiftUI

// MARK: - ProfileView: вкладка «Статистика», отметки счёта в играх, переход по уведомлениям

extension ProfileView {

    // MARK: - Вкладка «Статистика»

    var myStatsTab: some View {
        StatsDashboardView(
            store: matchesStore,
            userId: authService.currentUserId ?? "",
            isOwner: true,
            privacy: PrivacySettings(userData: userData),
            viewerPlan: authService.userProfile?.plan ?? .free
        )
    }

    // MARK: - Отметка счёта на карточке игры

    @ViewBuilder
    func matchChip(for game: [String: Any]) -> some View {
        if let requestId = game["documentId"] as? String,
           let myId = authService.currentUserId {

            let meeting = matchesStore.meetingMatches(forRequest: requestId)

            switch meeting.summary(for: myId) {
            case .single(let won, let lost, let isWin):
                Text("\(won):\(lost)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundColor(isWin ? AppColor.success : AppColor.textSecondary)
            case .several(let won, let lost):
                Text("\(won):\(lost) в матчах")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundColor(won > lost ? AppColor.success : AppColor.textSecondary)
            case .waitingForPartner:
                matchChipLabel("Ждём ответа", color: AppColor.textSecondary)
            case .disputedOnly:
                matchChipLabel("Счёт оспорен", color: AppColor.danger)
            case .needsYourAnswer, .none:
                // Здесь нужно действие: оно вынесено полосой внизу карточки (см. matchAction)
                EmptyView()
            }
        }
    }

    // Цвет — точка, слова — обычным цветом: читается на любом фоне
    private func matchChipLabel(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColor.textPrimary)
        }
        .padding(.horizontal, AppSpacing.s)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .cornerRadius(AppRadius.small)
    }

    /// Что нужно сделать со счётом: подпись для полосы внизу карточки игры. nil — ничего.
    func matchAction(for game: [String: Any]) -> String? {
        guard let requestId = game["documentId"] as? String,
              let myId = authService.currentUserId else { return nil }

        switch matchesStore.meetingMatches(forRequest: requestId).summary(for: myId) {
        case .needsYourAnswer: return "Подтвердите счёт"
        case .none:            return needsScore(game) ? "Внесите счёт" : nil
        default:               return nil
        }
    }

    /// Игра уже идёт или прошла, партнёр есть, счёта ещё нет
    private func needsScore(_ game: [String: Any]) -> Bool {
        guard let status = game["status"] as? String,
              ["in_progress", "completed"].contains(status),
              let partnerId = game["partnerId"] as? String, !partnerId.isEmpty else { return false }
        return true
    }

    // MARK: - Переход по тапу на уведомление

    /// Открывает игру (или сразу экран счёта), на которую указывает уведомление
    func openPendingNotificationTarget() {
        guard let target = appState.pendingNotificationTarget,
              let myId = authService.currentUserId else { return }
        appState.pendingNotificationTarget = nil

        // Уведомление об отмене ведёт в профиль того, кто отменил
        if target.opensProfile, let personId = target.targetId, !personId.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                profileToOpen = personId
            }
            return
        }

        guard target.opensGame, let requestId = target.targetId, !requestId.isEmpty else { return }

        sparringService.fetchRequest(id: requestId) { data in
            guard var game = data else { return }
            let authorId = game["userId"] as? String ?? ""
            let bookedBy = game["bookedBy"] as? String ?? ""
            // Открываем только свою игру
            guard myId == authorId || myId == bookedBy else { return }

            game["documentId"] = requestId
            game["partnerId"] = (myId == authorId) ? bookedBy : authorId

            // Небольшая пауза: центр уведомлений может ещё закрываться
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                bookedGameData = game
                bookedGameOpensMatch = target.opensMatch
                bookedGameOpensReview = target.opensReview
                bookedGameId = requestId
            }
        }
    }
}
