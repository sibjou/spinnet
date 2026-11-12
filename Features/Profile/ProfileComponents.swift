import SwiftUI
import FirebaseFirestore

// MARK: - Общие части профиля
// Эти компоненты использует и свой профиль, и профиль другого игрока,
// поэтому чужая страница выглядит так же, как своя.

// MARK: - Переключатель вкладок
struct ProfileTabBar: View {

    struct Item: Identifiable {
        let id: Int
        let title: String
        let icon: String
    }

    let items: [Item]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = item.id }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.subheadline)
                        Text(item.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.s)
                    .background(selection == item.id ? AppColor.background : Color.clear)
                    .foregroundColor(selection == item.id ? AppColor.primary : AppColor.textSecondary)
                    .cornerRadius(AppRadius.small)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.medium)
    }
}

// MARK: - Шапка профиля
struct ProfileHeaderView: View {
    let userId: String
    let firstName: String
    let lastName: String
    let city: String
    let skillLevel: String
    let grip: String
    let playStyle: String
    /// nil — показать прочерк (например, игрок скрыл статистику)
    let gamesCount: Int?
    let tournamentsCount: Int?
    let ttwRating: Int
    let averageRating: Double
    let reviewsCount: Int
    let onTapReviews: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.m) {
            InitialsAvatar(
                firstName: firstName,
                lastName: lastName,
                userId: userId,
                size: AppSize.avatarLarge
            )

            Text("\(firstName) \(lastName)")
                .font(.title2.bold())
                .foregroundColor(AppColor.textPrimary)

            if !city.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.caption)
                        .foregroundColor(AppColor.primary)
                    Text(city)
                        .font(.subheadline)
                        .foregroundColor(AppColor.textSecondary)
                }
            }

            HStack(spacing: AppSpacing.s) {
                levelBadge
                badge(grip)
                badge(playStyle)
            }

            statsBlock
                .padding(.horizontal, AppSpacing.l)
                .padding(.top, AppSpacing.s)
        }
    }

    private var statsBlock: some View {
        HStack(spacing: 0) {
            statItem(value: gamesCount.map { "\($0)" } ?? "—", title: "игр")
            Divider().frame(height: 40)
            statItem(value: tournamentsCount.map { "\($0)" } ?? "—", title: "турниров")
            Divider().frame(height: 40)
            // Рейтинг TTW есть не у всех: пустую колонку с прочерком не показываем
            if ttwRating > 0 {
                statItem(value: "\(ttwRating)", title: "рейтинг TTW")
                Divider().frame(height: 40)
            }

            Button(action: onTapReviews) {
                ratingItem
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, AppSpacing.m)
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.medium)
    }

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
            Text(reviewsCount > 0 ? "\(reviewsCount) \(Self.reviewsWord(reviewsCount))" : "отзывы")
                .font(.caption)
                .foregroundColor(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Уровень: четыре столбика и слово
    @ViewBuilder
    private var levelBadge: some View {
        if !skillLevel.isEmpty {
            HStack(spacing: 6) {
                LevelMeter(level: skillLevel)
                Text(skillLevel)
                    .font(.caption)
                    .foregroundColor(AppColor.textPrimary)
            }
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColor.cardBackground)
            .cornerRadius(AppRadius.small)
        }
    }

    @ViewBuilder
    private func badge(_ text: String) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(.caption)
                .foregroundColor(AppColor.textPrimary)
                .padding(.horizontal, AppSpacing.m)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColor.cardBackground)
                .cornerRadius(AppRadius.small)
        }
    }

    /// Склонение слова «отзыв»
    static func reviewsWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 14 { return "отзывов" }
        switch mod10 {
        case 1: return "отзыв"
        case 2, 3, 4: return "отзыва"
        default: return "отзывов"
        }
    }
}

// MARK: - Заглушка раздела (пусто или скрыто владельцем)
struct ProfilePlaceholder: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: AppSpacing.m) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(AppColor.textSecondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundColor(AppColor.textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
    }
}

// MARK: - Карточка турнира
struct ProfileTournamentCard: View {
    let tournament: [String: Any]
    var isCompleted: Bool = false

    var body: some View {
        VStack(spacing: 0) {

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
                        Text(AppDate.dayShort(timestamp.dateValue()))
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

            HStack {
                Image(systemName: "person.3.fill")
                    .font(.caption)
                    .foregroundColor(AppColor.textSecondary)
                Text("\((tournament["participants"] as? [String])?.count ?? 0) из \(tournament["maxParticipants"] as? Int ?? 0) участников")
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
