import SwiftUI
import FirebaseFirestore

// MARK: - ProfileView: шапка и статистика

extension ProfileView {
    // MARK: - Шапка профиля
    // Аватар + имя + город + бейджи + статистика

    var profileHeader: some View {
        VStack(spacing: AppSpacing.m) {
            // Аватар
            InitialsAvatar(
                firstName: userData["firstName"] as? String ?? "",
                lastName:  userData["lastName"]  as? String ?? "",
                userId:    authService.currentUserId ?? "",
                size: AppSize.avatarLarge
            )

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

    var statsBlock: some View {
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
    func statItem(value: String, title: String) -> some View {
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
    var ratingItem: some View {
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
    var ttwRatingDisplay: String {
        if let rating = userData["ttwRating"] as? Int, rating > 0 {
            return "\(rating)"
        }
        return "—"
    }

    // Склонение слова "отзыв"
    func reviewsWord(_ count: Int) -> String {
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
    func infoBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(AppColor.textPrimary)
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColor.cardBackground)
            .cornerRadius(AppRadius.small)
    }

    // Блок в статистике: крупное значение + подпись
    func statBlock(value: String, title: String) -> some View {
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
}
