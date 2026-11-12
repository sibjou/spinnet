import SwiftUI

// MARK: - Подписи к вариантам фильтров

extension String {
    /// «октябрь 2026 г.» → «Октябрь 2026 г.»
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

extension YearMonth {
    var title: String { AppDate.monthYear(firstDay()).capitalizedFirst }
}

extension HistoryPeriod {
    var title: String {
        switch self {
        case .allTime:    return "Всё время"
        case .last7Days:  return "7 дней"
        case .last30Days: return "30 дней"
        case .last90Days: return "3 месяца"
        case .thisYear:   return "Этот год"
        case .month(let month): return month.title
        }
    }
}

extension HistorySort {
    var title: String {
        switch self {
        case .newestFirst: return "Сначала новые"
        case .oldestFirst: return "Сначала старые"
        case .byOpponent:  return "По имени соперника"
        }
    }
}

extension GameRoleFilter {
    var title: String {
        switch self {
        case .any:     return "Все игры"
        case .created: return "Мои заявки"
        case .joined:  return "Я откликнулся"
        }
    }
}

extension GameOutcomeFilter {
    var title: String {
        switch self {
        case .any:     return "Любой результат"
        case .won:     return "Победы"
        case .lost:    return "Поражения"
        case .noScore: return "Без счёта"
        case .notHeld: return "Не состоялись"
        }
    }
}

extension MatchResultFilter {
    var title: String {
        switch self {
        case .any:  return "Все матчи"
        case .won:  return "Победы"
        case .lost: return "Поражения"
        }
    }
}

extension ReviewSort {
    var title: String {
        switch self {
        case .newest:        return "Сначала новые"
        case .oldest:        return "Сначала старые"
        case .highestRating: return "Сначала высокие оценки"
        case .lowestRating:  return "Сначала низкие оценки"
        }
    }
}

// MARK: - Заголовок месяца в списке

struct HistoryMonthHeader: View {
    let month: YearMonth
    let count: Int

    var body: some View {
        HStack {
            Text(month.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColor.textSecondary)
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundColor(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AppSpacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Кнопка-меню в панели фильтров

struct FilterMenuChip<Content: View>: View {
    let title: String
    let isActive: Bool
    let content: Content

    init(title: String, isActive: Bool, @ViewBuilder content: () -> Content) {
        self.title = title
        self.isActive = isActive
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundColor(isActive ? Color.white : AppColor.textPrimary)
            .background(isActive ? AppColor.primary : AppColor.cardBackground)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Поле поиска

struct FilterSearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColor.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit { isFocused = false }      // «Найти» убирает клавиатуру — список виден целиком
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, AppSpacing.m)
        .padding(.vertical, 9)
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.medium)
    }
}

// MARK: - Подпись под панелью: «Показано 3 из 48» и сброс

struct FilterSummaryRow: View {
    let shown: Int
    let total: Int
    let isActive: Bool
    let onReset: () -> Void

    var body: some View {
        HStack {
            Text(isActive ? "Показано \(shown) из \(total)" : "Всего: \(total)")
                .font(.caption)
                .foregroundColor(AppColor.textSecondary)
            Spacer()
            if isActive {
                Button("Сбросить", action: onReset)
                    .font(.caption.weight(.semibold))
            }
        }
    }
}

// MARK: - Ничего не нашлось

struct FilterEmptyResult: View {
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 36))
                .foregroundColor(AppColor.textTertiary)
            Text("Ничего не найдено")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColor.textSecondary)
            Button("Сбросить фильтры", action: onReset)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
    }
}

// MARK: - Панель фильтров игр

struct GameHistoryFilterBar: View {
    @Binding var filter: GameHistoryFilter
    let games: [HistoryGame]            // все игры, без фильтра: из них считаются месяцы, города и числа
    let shownCount: Int

    private var months: [MonthBucket] { HistoryBuckets.months(of: games.map { $0.date }) }
    private var cities: [String] { GameHistoryFilter.cities(in: games) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            FilterSearchField(placeholder: "Имя, город или место", text: $filter.query)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.s) {
                    periodChip
                    roleChip
                    outcomeChip
                    if cities.count > 1 { cityChip }
                    sortChip
                }
            }

            FilterSummaryRow(shown: shownCount, total: games.count, isActive: filter.isActive) {
                withAnimation { filter.reset() }
            }
        }
    }

    private var periodChip: some View {
        FilterMenuChip(title: filter.period.isAllTime ? "Период" : filter.period.title,
                       isActive: !filter.period.isAllTime) {
            Picker("Период", selection: $filter.period) {
                ForEach(HistoryPeriod.quick, id: \.self) { period in
                    Text(period.title).tag(period)
                }
            }
            // Только те месяцы, в которые что-то было, — с числом игр
            if !months.isEmpty {
                Section("По месяцам") {
                    Picker("Месяц", selection: $filter.period) {
                        ForEach(months, id: \.month) { bucket in
                            Text("\(bucket.month.title) (\(bucket.count))").tag(HistoryPeriod.month(bucket.month))
                        }
                    }
                }
            }
        }
    }

    private var roleChip: some View {
        FilterMenuChip(title: filter.role == .any ? "Роль" : filter.role.title, isActive: filter.role != .any) {
            Picker("Роль", selection: $filter.role) {
                ForEach(GameRoleFilter.allCases, id: \.self) { role in
                    Text(role.title).tag(role)
                }
            }
        }
    }

    private var outcomeChip: some View {
        FilterMenuChip(title: filter.outcome == .any ? "Результат" : filter.outcome.title,
                       isActive: filter.outcome != .any) {
            Picker("Результат", selection: $filter.outcome) {
                ForEach(GameOutcomeFilter.allCases, id: \.self) { outcome in
                    let count = GameHistoryFilter.count(of: outcome, in: games)
                    Text(outcome == .any ? outcome.title : "\(outcome.title) (\(count))").tag(outcome)
                }
            }
        }
    }

    private var cityChip: some View {
        FilterMenuChip(title: filter.city ?? "Город", isActive: filter.city != nil) {
            Picker("Город", selection: $filter.city) {
                Text("Все города").tag(String?.none)
                ForEach(cities, id: \.self) { city in
                    Text(city).tag(String?.some(city))
                }
            }
        }
    }

    private var sortChip: some View {
        FilterMenuChip(title: filter.sort.title, isActive: false) {
            Picker("Сортировка", selection: $filter.sort) {
                ForEach(HistorySort.allCases, id: \.self) { sort in
                    Text(sort.title).tag(sort)
                }
            }
        }
    }
}

// MARK: - Панель фильтров матчей

struct MatchHistoryFilterBar: View {
    @Binding var filter: MatchHistoryFilter
    let matches: [HistoryMatch]
    let shownCount: Int

    private var months: [MonthBucket] { HistoryBuckets.months(of: matches.map { $0.date }) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            FilterSearchField(placeholder: "Имя соперника", text: $filter.query)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.s) {
                    FilterMenuChip(title: filter.period.isAllTime ? "Период" : filter.period.title,
                                   isActive: !filter.period.isAllTime) {
                        Picker("Период", selection: $filter.period) {
                            ForEach(HistoryPeriod.quick, id: \.self) { period in
                                Text(period.title).tag(period)
                            }
                        }
                        if !months.isEmpty {
                            Section("По месяцам") {
                                Picker("Месяц", selection: $filter.period) {
                                    ForEach(months, id: \.month) { bucket in
                                        Text("\(bucket.month.title) (\(bucket.count))").tag(HistoryPeriod.month(bucket.month))
                                    }
                                }
                            }
                        }
                    }

                    FilterMenuChip(title: filter.result == .any ? "Результат" : filter.result.title,
                                   isActive: filter.result != .any) {
                        Picker("Результат", selection: $filter.result) {
                            ForEach(MatchResultFilter.allCases, id: \.self) { result in
                                let count = MatchHistoryFilter.count(of: result, in: matches)
                                Text("\(result.title) (\(count))").tag(result)
                            }
                        }
                    }

                    FilterMenuChip(title: filter.sort.title, isActive: false) {
                        Picker("Сортировка", selection: $filter.sort) {
                            ForEach(HistorySort.allCases, id: \.self) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                    }
                }
            }

            FilterSummaryRow(shown: shownCount, total: matches.count, isActive: filter.isActive) {
                withAnimation { filter.reset() }
            }
        }
    }
}

// MARK: - Панель фильтров отзывов: гистограмма оценок, «только с текстом», сортировка

struct ReviewFilterBar<R: RatedReview>: View {
    @Binding var filter: ReviewFilter
    let reviews: [R]
    let shownCount: Int

    private var distribution: [Int: Int] { ReviewFilter.distribution(of: reviews) }
    private var withCommentCount: Int { ReviewFilter.withComment(in: reviews) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            // Строки гистограммы нажимаются: нажали на «5 звёзд» — остались только пятёрки
            VStack(spacing: 6) {
                ForEach([5, 4, 3, 2, 1], id: \.self) { stars in
                    distributionRow(stars: stars)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.s) {
                    Button {
                        withAnimation { filter.onlyWithComment.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filter.onlyWithComment ? "checkmark" : "text.bubble")
                                .font(.caption.weight(.bold))
                            Text("С текстом (\(withCommentCount))")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundColor(filter.onlyWithComment ? Color.white : AppColor.textPrimary)
                        .background(filter.onlyWithComment ? AppColor.primary : AppColor.cardBackground)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    FilterMenuChip(title: filter.sort.title, isActive: false) {
                        Picker("Сортировка", selection: $filter.sort) {
                            ForEach(ReviewSort.allCases, id: \.self) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                    }
                }
            }

            FilterSummaryRow(shown: shownCount, total: reviews.count, isActive: filter.isActive) {
                withAnimation { filter.reset() }
            }
        }
    }

    private func distributionRow(stars: Int) -> some View {
        let count = distribution[stars] ?? 0
        let maxCount = max(distribution.values.max() ?? 1, 1)
        let selected = filter.rating == stars

        return Button {
            withAnimation { filter.rating = selected ? nil : stars }
        } label: {
            HStack(spacing: AppSpacing.s) {
                Text("\(stars)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(width: 10)
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundColor(AppColor.star)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColor.cardBackground)
                        Capsule()
                            .fill(selected ? AppColor.primary : AppColor.star.opacity(0.8))
                            .frame(width: proxy.size.width * CGFloat(count) / CGFloat(maxCount))
                    }
                }
                .frame(height: 8)

                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(AppColor.textSecondary)
                    .frame(width: 28, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .opacity(filter.rating == nil || selected ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .accessibilityLabel("\(stars) из 5: \(count)")
    }
}
