import SwiftUI
import Charts

// MARK: - Вкладка «Статистика»
// Один и тот же экран для своего профиля и чужого. Что показывать другим,
// решает владелец (PrivacySettings); что из этого платное — FeatureGate.
struct StatsDashboardView: View {
    @ObservedObject var store: PlayerMatchesStore
    let userId: String
    let isOwner: Bool
    let privacy: PrivacySettings
    let viewerPlan: Plan

    private static let weekdayTitles = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    var body: some View {
        VStack(spacing: AppSpacing.l) {
            if !privacy.canView(.stats, isOwner: isOwner) {
                ProfilePlaceholder(
                    icon: "lock.fill",
                    title: "Статистика скрыта",
                    subtitle: "Игрок не показывает статистику другим"
                )
            } else if store.isLoading && !store.hasLoaded {
                ProgressView().padding(.top, AppSpacing.xxl)
            } else if store.stats.matches == 0 {
                ProfilePlaceholder(
                    icon: "chart.bar.xaxis",
                    title: "Пока нет подтверждённых матчей",
                    subtitle: isOwner
                        ? "Сыграйте и внесите счёт: после подтверждения партнёром матч появится здесь"
                        : "Здесь появится статистика, когда игрок сыграет матчи с подтверждённым счётом"
                )
            } else {
                content(store.stats)
            }
        }
    }

    // MARK: - Содержимое

    @ViewBuilder
    private func content(_ stats: PlayerStats) -> some View {
        overview(stats)
        formCard(stats)
        scoreCard(stats)

        PremiumGate(feature: .statsCharts, plan: viewerPlan) {
            VStack(spacing: AppSpacing.l) {
                weeklyChart(stats)
                trendChart(stats)
            }
        }

        PremiumGate(feature: .statsHeatmap, plan: viewerPlan) {
            heatmapCard(stats)
        }

        if privacy.canView(.matchHistory, isOwner: isOwner) {
            PremiumGate(feature: .statsHeadToHead, plan: viewerPlan) {
                headToHeadCard(stats)
            }
        } else {
            ProfilePlaceholder(
                icon: "lock.fill",
                title: "Соперники скрыты",
                subtitle: "Игрок не показывает соперников"
            )
        }

        detailsCard(stats)
    }

    // MARK: - Сводка

    private func overview(_ stats: PlayerStats) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: AppSpacing.m), GridItem(.flexible())],
            spacing: AppSpacing.m
        ) {
            tile(value: "\(stats.matches)", title: "матчей", caption: "\(stats.uniqueOpponents) \(Self.opponentsWord(stats.uniqueOpponents))")
            tile(value: "\(Int((stats.winRate * 100).rounded()))%", title: "побед", caption: "\(stats.wins) из \(stats.matches)")
            tile(value: Self.streakText(stats.currentStreak), title: "серия", caption: "лучшая серия побед: \(stats.bestWinStreak)")
            tile(value: Self.hoursText(stats.totalHours), title: "на корте", caption: "по времени встреч")
        }
    }

    private func tile(value: String, title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(AppColor.textPrimary)
            Text(caption)
                .font(.caption)
                .foregroundColor(AppColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.l)
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.large)
    }

    // MARK: - Форма

    private func formCard(_ stats: PlayerStats) -> some View {
        card(title: "Форма", subtitle: "последние \(stats.form.count)") {
            // Победа — закрашенная плитка, поражение — пустая с рамкой: различаются не только цветом
            HStack(spacing: 6) {
                ForEach(stats.form.indices, id: \.self) { index in
                    let won = stats.form[index]
                    Text(won ? "В" : "П")
                        .font(.caption.weight(.bold))
                        .foregroundColor(won ? .white : AppColor.danger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(won ? AppColor.success : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(won ? Color.clear : AppColor.danger, lineWidth: 1.5)
                        )
                        .cornerRadius(6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Последние матчи: " + stats.form.map { $0 ? "победа" : "поражение" }.joined(separator: ", "))
        }
    }

    // MARK: - Партии и очки

    private func scoreCard(_ stats: PlayerStats) -> some View {
        card(title: "Партии и очки", subtitle: nil) {
            VStack(spacing: AppSpacing.l) {
                ratioRow(title: "Партии", won: stats.gamesWon, lost: stats.gamesLost)
                ratioRow(title: "Очки", won: stats.pointsWon, lost: stats.pointsLost)
            }
        }
    }

    private func ratioRow(title: String, won: Int, lost: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColor.textPrimary)
                Spacer()
                Text("\(won) : \(lost)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(AppColor.textSecondary)
            }
            GeometryReader { geometry in
                let total = max(won + lost, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray4))
                    Capsule()
                        .fill(AppColor.primary)
                        .frame(width: geometry.size.width * CGFloat(won) / CGFloat(total))
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Активность по неделям

    private func weeklyChart(_ stats: PlayerStats) -> some View {
        card(title: "Активность", subtitle: "матчи по неделям, 12 недель") {
            Chart {
                ForEach(stats.weekly) { week in
                    BarMark(
                        x: .value("Неделя", week.weekStart, unit: .weekOfYear),
                        y: .value("Матчи", week.wins)
                    )
                    .foregroundStyle(by: .value("Результат", "Победы"))

                    BarMark(
                        x: .value("Неделя", week.weekStart, unit: .weekOfYear),
                        y: .value("Матчи", week.matches - week.wins)
                    )
                    .foregroundStyle(by: .value("Результат", "Поражения"))
                }
            }
            .chartForegroundStyleScale([
                "Победы": AppColor.primary,
                "Поражения": Color(.systemGray3)
            ])
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 170)
        }
    }

    // MARK: - Динамика побед

    private func trendChart(_ stats: PlayerStats) -> some View {
        card(title: "Динамика", subtitle: "доля побед за последние 10 матчей") {
            if stats.trend.count < 2 {
                Text("График появится после четвёртого матча")
                    .font(.subheadline)
                    .foregroundColor(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart {
                    RuleMark(y: .value("50%", 50.0))
                        .foregroundStyle(Color(.systemGray3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    ForEach(stats.trend) { point in
                        LineMark(
                            x: .value("Матч", point.index),
                            y: .value("Побед, %", point.winRate * 100)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(AppColor.primary)

                        PointMark(
                            x: .value("Матч", point.index),
                            y: .value("Побед, %", point.winRate * 100)
                        )
                        .symbolSize(30)
                        .foregroundStyle(AppColor.primary)
                    }
                }
                .chartYScale(domain: 0.0...100.0)
                .chartYAxis {
                    AxisMarks(values: [0.0, 50.0, 100.0]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let percent = value.as(Double.self) { Text("\(Int(percent))%") }
                        }
                    }
                }
                .frame(height: 150)
            }
        }
    }

    // MARK: - Когда играете

    private func heatmapCard(_ stats: PlayerStats) -> some View {
        let maxCount = max(stats.heatmap.map { $0.count }.max() ?? 1, 1)

        return card(title: "Когда играете", subtitle: bestTimeText(stats)) {
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    ForEach(Self.weekdayTitles, id: \.self) { title in
                        Text(title)
                            .font(.caption2)
                            .foregroundColor(AppColor.textSecondary)
                    }
                }
                ForEach(DayPart.allCases) { part in
                    GridRow {
                        Text(part.title)
                            .font(.caption2)
                            .foregroundColor(AppColor.textSecondary)
                            .gridColumnAlignment(.leading)
                        ForEach(1...7, id: \.self) { weekday in
                            let count = cellCount(stats, weekday: weekday, part: part)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppColor.primary.opacity(
                                    count == 0 ? 0.08 : 0.25 + 0.75 * Double(count) / Double(maxCount)
                                ))
                                .frame(height: 28)
                                .overlay {
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.caption2.weight(.bold))
                                            .foregroundColor(.white)
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private func cellCount(_ stats: PlayerStats, weekday: Int, part: DayPart) -> Int {
        stats.heatmap.first { $0.weekday == weekday && $0.dayPart == part }?.count ?? 0
    }

    private func bestTimeText(_ stats: PlayerStats) -> String? {
        guard let best = stats.heatmap.max(by: { $0.count < $1.count }), best.count > 0 else { return nil }
        let day = Self.weekdayTitles[best.weekday - 1]
        return "чаще всего: \(day), \(best.dayPart.title.lowercased())"
    }

    // MARK: - Личные встречи

    private func headToHeadCard(_ stats: PlayerStats) -> some View {
        card(title: "Соперники",
             subtitle: isOwner ? "с кем вы играли чаще всего, счёт побед и поражений"
                               : "с кем игрок играл чаще всего, счёт побед и поражений") {
            VStack(spacing: AppSpacing.m) {
                ForEach(Array(stats.headToHead.prefix(5))) { item in
                    NavigationLink {
                        PlayerProfileView(userId: item.opponentId)
                    } label: {
                        HStack(spacing: AppSpacing.m) {
                            InitialsAvatar(fullName: store.name(of: item.opponentId), userId: item.opponentId, size: AppSize.avatarSmall)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.name(of: item.opponentId))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(AppColor.textPrimary)
                                    .lineLimit(1)
                                Text("\(item.matches) \(Self.matchesWord(item.matches))")
                                    .font(.caption)
                                    .foregroundColor(AppColor.textSecondary)
                            }
                            Spacer()
                            Text("\(item.wins) – \(item.losses)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundColor(AppColor.textPrimary)
                                .accessibilityLabel("побед \(item.wins), поражений \(item.losses)")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Подробнее

    private func detailsCard(_ stats: PlayerStats) -> some View {
        card(title: "Подробнее", subtitle: nil) {
            VStack(spacing: AppSpacing.m) {
                detailRow("Решающие партии",
                          stats.deciderMatches == 0 ? "—" : "\(stats.deciderWins) из \(stats.deciderMatches) выиграно")
                Divider()
                detailRow("Разница очков за матч", String(format: "%+.1f", stats.averagePointDifference))
                Divider()
                detailRow("Лучшая серия побед", "\(stats.bestWinStreak)")
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(AppColor.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColor.textPrimary)
        }
    }

    // MARK: - Оболочка карточки

    private func card<Inner: View>(title: String, subtitle: String?, @ViewBuilder content: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppColor.textSecondary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.l)
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.large)
    }

    // MARK: - Подписи

    static func streakText(_ streak: Int) -> String {
        if streak > 0 { return "\(streak) В" }
        if streak < 0 { return "\(-streak) П" }
        return "—"
    }

    static func hoursText(_ hours: Double) -> String {
        if hours < 1 { return "\(Int((hours * 60).rounded())) мин" }
        let rounded = (hours * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded)) ч" : String(format: "%.1f ч", rounded)
    }

    static func matchesWord(_ count: Int) -> String {
        let mod10 = count % 10, mod100 = count % 100
        if mod100 >= 11 && mod100 <= 14 { return "матчей" }
        switch mod10 {
        case 1: return "матч"
        case 2, 3, 4: return "матча"
        default: return "матчей"
        }
    }

    static func opponentsWord(_ count: Int) -> String {
        let mod10 = count % 10, mod100 = count % 100
        if mod100 >= 11 && mod100 <= 14 { return "соперников" }
        switch mod10 {
        case 1: return "соперник"
        case 2, 3, 4: return "соперника"
        default: return "соперников"
        }
    }
}
