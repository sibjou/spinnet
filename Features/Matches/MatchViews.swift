import SwiftUI

// MARK: - Карточка счёта
// Счёт «глазами» левого игрока: его очки слева.
struct MatchScoreCard: View {
    let games: [GameScore]
    let format: MatchFormat
    let leftName: String
    let rightName: String

    var body: some View {
        let result = MatchScoring.validate(games, format: format).result

        VStack(spacing: AppSpacing.m) {
            HStack(alignment: .center) {
                Text(leftName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColor.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(result.map { "\($0.gamesWonA) : \($0.gamesWonB)" } ?? "— : —")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.textPrimary)

                Text(rightName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColor.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Divider()

            ForEach(games.indices, id: \.self) { index in
                HStack {
                    Text("Партия \(index + 1)")
                        .font(.subheadline)
                        .foregroundColor(AppColor.textSecondary)
                    Spacer()
                    Text("\(games[index].a) : \(games[index].b)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundColor(AppColor.textPrimary)
                }
            }
        }
        .padding(AppSpacing.l)
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.large)
    }
}

// MARK: - Экран матча: внести, подтвердить, предложить свой, оспорить
struct MatchView: View {
    let requestId: String
    let myId: String
    let myName: String
    let partnerId: String
    let partnerName: String
    /// Я — автор заявки (игрок A)
    let iAmAuthor: Bool
    /// Какой по счёту матч встречи: 1, 2, 3 …
    var ordinal: Int = 1
    var onChanged: (Match?) -> Void = { _ in }

    // Режим ввода счёта
    private enum EntryMode: Identifiable {
        case new
        case edit(Match)
        case counter(Match)

        var id: String {
            switch self {
            case .new:     return "new"
            case .edit:    return "edit"
            case .counter: return "counter"
            }
        }
    }

    @State private var match: Match?
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var entry: EntryMode?
    @State private var errorMessage: String?
    @State private var showDisputeConfirm = false

    private var me: MatchActor { MatchActor(id: myId, name: myName) }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.l) {
                playersHeader

                if isLoading {
                    ProgressView().padding(.top, AppSpacing.xl)
                } else if let match {
                    matchContent(match)
                } else {
                    emptyContent
                }

                if isWorking {
                    ProgressView()
                }
            }
            .padding(AppSpacing.l)
        }
        .background(AppColor.background)
        .navigationTitle("Матч \(ordinal)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $entry) { mode in
            entrySheet(for: mode)
        }
        .alert("Оспорить счёт?", isPresented: $showDisputeConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Оспорить", role: .destructive) {
                if let match { run { done in MatchService.shared.dispute(seen: match, player: me, completion: done) } }
            }
        } message: {
            Text("Матч не будет учтён в статистике. Если вы просто хотите исправить счёт — внесите свой вариант.")
        }
        .alert("Счёт матча", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear { load() }
    }

    // MARK: - Игроки

    private var playersHeader: some View {
        HStack(spacing: AppSpacing.l) {
            VStack(spacing: 6) {
                InitialsAvatar(fullName: myName, userId: myId, size: AppSize.avatarMedium)
                Text("Вы").font(.caption).foregroundColor(AppColor.textSecondary)
            }
            Text("против")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColor.textSecondary)
            NavigationLink {
                PlayerProfileView(userId: partnerId)
            } label: {
                VStack(spacing: 6) {
                    InitialsAvatar(fullName: partnerName, userId: partnerId, size: AppSize.avatarMedium)
                    Text(partnerName)
                        .font(.caption)
                        .foregroundColor(AppColor.textSecondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Нет счёта

    private var emptyContent: some View {
        VStack(spacing: AppSpacing.l) {
            ProfilePlaceholder(
                icon: "list.clipboard",
                title: ordinal > 1 ? "Счёт матча \(ordinal) ещё не внесён" : "Счёт ещё не внесён",
                subtitle: "Внести результат может любой из вас. \(partnerName) получит уведомление и подтвердит его или внесёт свой счёт."
            )
            Button("Внести счёт") { entry = .new }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isWorking)
        }
    }

    // MARK: - Есть счёт

    @ViewBuilder
    private func matchContent(_ match: Match) -> some View {
        switch match.status {
        case .confirmed: confirmedContent(match)
        case .disputed:  disputedContent(match)
        case .proposed:  proposedContent(match)
        }
    }

    private func scoreCard(_ match: Match) -> some View {
        MatchScoreCard(
            games: match.games(for: myId),
            format: match.format,
            leftName: "Вы",
            rightName: partnerName
        )
    }

    private func confirmedContent(_ match: Match) -> some View {
        VStack(spacing: AppSpacing.l) {
            scoreCard(match)
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "checkmark.seal.fill").foregroundColor(AppColor.success)
                Text(match.winnerId == myId ? "Победа. Матч подтверждён и учтён в статистике" : "Поражение. Матч подтверждён и учтён в статистике")
                    .font(.subheadline)
                    .foregroundColor(AppColor.textSecondary)
            }
        }
    }

    private func disputedContent(_ match: Match) -> some View {
        VStack(spacing: AppSpacing.l) {
            scoreCard(match)
            HStack(alignment: .top, spacing: AppSpacing.s) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(AppColor.warning)
                Text("Счёт оспорен, матч не учитывается в статистике. Если это недоразумение, договоритесь и сыграйте снова.")
                    .font(.subheadline)
                    .foregroundColor(AppColor.textSecondary)
            }
        }
    }

    private func proposedContent(_ match: Match) -> some View {
        VStack(spacing: AppSpacing.l) {
            scoreCard(match)

            if match.awaitsResponse(from: myId) {
                Text(match.revision >= 2
                     ? "\(partnerName) предлагает другой счёт. Подтвердите его или оспорьте."
                     : "\(partnerName) внёс результат игры. Если всё верно — подтвердите, если нет — внесите свой счёт.")
                    .font(.subheadline)
                    .foregroundColor(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if match.revision >= 2, let previous = previousVersionText(match) {
                    Text("Ваш вариант был: \(previous)")
                        .font(.footnote)
                        .foregroundColor(AppColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("Подтвердить счёт") {
                    run { done in MatchService.shared.confirm(seen: match, player: me, completion: done) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isWorking)

                if match.canCounter(by: myId) {
                    Button("Внести свой счёт") { entry = .counter(match) }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(isWorking)
                }

                Button("Оспорить", role: .destructive) { showDisputeConfirm = true }
                    .disabled(isWorking)
            } else if match.canEdit(by: myId) {
                Text("Ждём подтверждения от \(partnerName). Матч попадёт в статистику, когда партнёр подтвердит счёт.")
                    .font(.subheadline)
                    .foregroundColor(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Исправить счёт") { entry = .edit(match) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isWorking)
            }
        }
    }

    /// Предыдущая версия счёта — со стороны текущего игрока
    private func previousVersionText(_ match: Match) -> String? {
        guard let previous = match.previousGames, !previous.isEmpty else { return nil }
        let mine = iAmAuthor ? previous : previous.map { GameScore(a: $0.b, b: $0.a) }
        return MatchScoring.gamesDescription(mine)
    }

    // MARK: - Ввод счёта

    @ViewBuilder
    private func entrySheet(for mode: EntryMode) -> some View {
        switch mode {
        case .new:
            MatchEntryView(
                title: "Внести счёт",
                partnerName: partnerName,
                iAmAuthor: iAmAuthor,
                initialGames: [],
                initialFormat: .bestOf5,
                note: nil
            ) { games, format in
                run { done in
                    MatchService.shared.propose(requestId: requestId, ordinal: ordinal, games: games, format: format, player: me, completion: done)
                }
            }
        case .edit(let existing):
            MatchEntryView(
                title: "Исправить счёт",
                partnerName: partnerName,
                iAmAuthor: iAmAuthor,
                initialGames: existing.games,
                initialFormat: existing.format,
                note: nil
            ) { games, format in
                run { done in
                    MatchService.shared.propose(requestId: requestId, ordinal: ordinal, games: games, format: format, player: me, completion: done)
                }
            }
        case .counter(let existing):
            MatchEntryView(
                title: "Ваш счёт",
                partnerName: partnerName,
                iAmAuthor: iAmAuthor,
                initialGames: [],
                initialFormat: existing.format,
                note: "\(partnerName) внёс: \(MatchScoring.gamesDescription(existing.games(for: myId)))"
            ) { games, format in
                run { done in
                    MatchService.shared.counter(seen: existing, games: games, format: format, player: me, completion: done)
                }
            }
        }
    }

    // MARK: - Загрузка и действия

    private func load() {
        MatchService.shared.fetchMatch(documentId: MatchIds.documentId(requestId: requestId, ordinal: ordinal)) { loaded in
            match = loaded
            isLoading = false
            onChanged(loaded)
        }
    }

    private func run(_ operation: (@escaping (Result<Match, MatchError>) -> Void) -> Void) {
        isWorking = true
        operation { result in
            isWorking = false
            switch result {
            case .success(let updated):
                match = updated
                onChanged(updated)
            case .failure(let error):
                errorMessage = error.message
                load()
            }
        }
    }
}

// MARK: - Ввод счёта по партиям
struct MatchEntryView: View {
    let title: String
    let partnerName: String
    let iAmAuthor: Bool
    let note: String?
    /// Счёт в ориентации «A — автор заявки»
    let onSubmit: ([GameScore], MatchFormat) -> Void

    @Environment(\.dismiss) private var dismiss

    private struct GameRow: Equatable {
        var mine = ""
        var theirs = ""
    }

    @State private var format: MatchFormat
    @State private var rows: [GameRow]

    init(title: String,
         partnerName: String,
         iAmAuthor: Bool,
         initialGames: [GameScore],
         initialFormat: MatchFormat,
         note: String?,
         onSubmit: @escaping ([GameScore], MatchFormat) -> Void) {
        self.title = title
        self.partnerName = partnerName
        self.iAmAuthor = iAmAuthor
        self.note = note
        self.onSubmit = onSubmit

        var initialRows = Array(repeating: GameRow(), count: MatchFormat.bestOf7.rawValue)
        for (index, game) in initialGames.enumerated() where index < initialRows.count {
            let mine   = iAmAuthor ? game.a : game.b
            let theirs = iAmAuthor ? game.b : game.a
            initialRows[index] = GameRow(mine: "\(mine)", theirs: "\(theirs)")
        }
        _rows = State(initialValue: initialRows)
        _format = State(initialValue: initialFormat)
    }

    // MARK: Разбор введённого

    /// Партия из строки: «a» — мои очки
    private func game(at index: Int) -> GameScore? {
        guard rows.indices.contains(index),
              let mine = Int(rows[index].mine.trimmingCharacters(in: .whitespaces)),
              let theirs = Int(rows[index].theirs.trimmingCharacters(in: .whitespaces)) else { return nil }
        return GameScore(a: mine, b: theirs)
    }

    /// Сколько строк показывать: все заполненные верно + одна для следующей партии
    private var visibleRows: Int {
        var visible = 1
        var winsMine = 0
        var winsTheirs = 0
        for index in 0..<format.rawValue {
            guard let parsed = game(at: index), MatchScoring.isValidGame(parsed) else { break }
            if parsed.a > parsed.b { winsMine += 1 } else { winsTheirs += 1 }
            if winsMine == format.gamesToWin || winsTheirs == format.gamesToWin { return index + 1 }
            visible = min(index + 2, format.rawValue)
        }
        return visible
    }

    private var enteredGames: [GameScore] {
        var result: [GameScore] = []
        for index in 0..<visibleRows {
            guard let parsed = game(at: index) else { break }
            result.append(parsed)
        }
        return result
    }

    private var validation: MatchScoring.Validation {
        MatchScoring.validate(enteredGames, format: format)
    }

    private func message(forRow index: Int) -> String? {
        if case .invalid(let gameIndex, let text) = validation, gameIndex == index { return text }
        let row = rows[index]
        if game(at: index) == nil, !(row.mine.isEmpty && row.theirs.isEmpty) {
            return "Введите очки обоих игроков"
        }
        return nil
    }

    // MARK: Экран

    var body: some View {
        NavigationStack {
            Form {
                if let note {
                    Section {
                        Text(note)
                            .font(.subheadline)
                            .foregroundColor(AppColor.textSecondary)
                    }
                }

                Section("Формат матча") {
                    Picker("Формат", selection: $format) {
                        ForEach(MatchFormat.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    HStack {
                        Spacer()
                        Text("Вы")
                            .frame(width: 64)
                        Text(partnerName)
                            .lineLimit(1)
                            .frame(width: 64)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColor.textSecondary)

                    ForEach(0..<visibleRows, id: \.self) { index in
                        gameRow(index)
                    }
                } header: {
                    Text("Счёт по партиям")
                } footer: {
                    Text("Партия идёт до 11 очков, при 10:10 — до разницы в 2 очка.")
                }

                Section {
                    summary
                }

                Section {
                    Button("Отправить на подтверждение") { submit() }
                        .disabled(!validation.isValid)
                } footer: {
                    Text("Счёт попадёт в статистику, когда партнёр его подтвердит.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                }
            }
        }
    }

    private func gameRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Партия \(index + 1)")
                Spacer()
                scoreField($rows[index].mine)
                Text(":").foregroundColor(AppColor.textTertiary)
                scoreField($rows[index].theirs)
            }
            if let text = message(forRow: index) {
                Text(text)
                    .font(.caption)
                    .foregroundColor(AppColor.danger)
            }
        }
    }

    private func scoreField(_ text: Binding<String>) -> some View {
        TextField("0", text: text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .frame(width: 56)
            .onChange(of: text.wrappedValue) { _, newValue in
                let cleaned = String(newValue.filter { $0.isNumber }.prefix(2))
                if cleaned != newValue { text.wrappedValue = cleaned }
            }
    }

    @ViewBuilder
    private var summary: some View {
        switch validation {
        case .valid(let result):
            Label(
                result.winner == .a
                    ? "Вы выиграли \(result.gamesWonA):\(result.gamesWonB)"
                    : "Победил \(partnerName), \(result.gamesWonB):\(result.gamesWonA)",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundColor(AppColor.success)
        case .incomplete(let text):
            Label(text, systemImage: "ellipsis.circle")
                .foregroundColor(AppColor.textSecondary)
        case .invalid:
            Label("Исправьте счёт в отмеченной партии", systemImage: "exclamationmark.circle.fill")
                .foregroundColor(AppColor.danger)
        }
    }

    private func submit() {
        guard validation.isValid else { return }
        // Из «моей» ориентации в «A — автор заявки»
        let games = enteredGames.map { iAmAuthor ? $0 : GameScore(a: $0.b, b: $0.a) }
        onSubmit(games, format)
        dismiss()
    }
}

// MARK: - Матчи одной встречи
// За встречу можно сыграть несколько матчей: у каждого свой счёт и своё подтверждение.
struct MeetingMatchesView: View {
    let requestId: String
    let myId: String
    let myName: String
    let partnerId: String
    let partnerName: String
    let iAmAuthor: Bool
    /// Перейти сразу к матчу, который ждёт ответа (переход по уведомлению)
    var autoOpenPending: Bool = false
    var onChanged: (MeetingMatches) -> Void = { _ in }

    @State private var meeting = MeetingMatches([])
    @State private var isLoading = true
    @State private var openedOrdinal = 1
    @State private var showMatch = false
    @State private var didAutoOpen = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.l) {
                if isLoading {
                    ProgressView().padding(.top, AppSpacing.xl)
                } else if meeting.isEmpty {
                    emptyContent
                } else {
                    summaryHeader
                    ForEach(meeting.matches) { match in
                        matchRow(match)
                    }
                    addMatchSection
                }
            }
            .padding(AppSpacing.l)
        }
        .background(AppColor.background)
        .navigationTitle("Счёт встречи")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showMatch) {
            MatchView(
                requestId: requestId,
                myId: myId,
                myName: myName,
                partnerId: partnerId,
                partnerName: partnerName,
                iAmAuthor: iAmAuthor,
                ordinal: openedOrdinal,
                onChanged: { _ in load() }
            )
        }
        .onAppear { load() }
    }

    // MARK: Части экрана

    private var emptyContent: some View {
        VStack(spacing: AppSpacing.l) {
            ProfilePlaceholder(
                icon: "list.clipboard",
                title: "Счёт ещё не внесён",
                subtitle: "Внести результат может любой из вас. \(partnerName) получит уведомление и подтвердит его. Если сыграете несколько матчей, каждый вносится отдельно."
            )
            Button("Внести счёт") { open(ordinal: 1) }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    @ViewBuilder
    private var summaryHeader: some View {
        let record = meeting.record(for: myId)
        if meeting.confirmed.count > 1 {
            VStack(spacing: 4) {
                Text("\(record.won) : \(record.lost)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.textPrimary)
                Text("Итог встречи по подтверждённым матчам")
                    .font(.caption)
                    .foregroundColor(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.l)
            .background(AppColor.cardBackground)
            .cornerRadius(AppRadius.large)
        }
    }

    private func matchRow(_ match: Match) -> some View {
        Button {
            open(ordinal: match.ordinal)
        } label: {
            HStack(spacing: AppSpacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Матч \(match.ordinal)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColor.textPrimary)
                    Text(statusText(match))
                        .font(.caption)
                        .foregroundColor(statusColor(match))
                }
                Spacer()
                if let perspective = match.perspective(of: myId) {
                    Text("\(perspective.gamesWon) : \(perspective.gamesLost)")
                        .font(.headline.monospacedDigit())
                        .foregroundColor(match.status == .confirmed && perspective.won ? AppColor.success : AppColor.textPrimary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(AppColor.textTertiary)
            }
            .padding(AppSpacing.m)
            .background(AppColor.cardBackground)
            .cornerRadius(AppRadius.medium)
        }
        .buttonStyle(.plain)
    }

    private func statusText(_ match: Match) -> String {
        switch match.status {
        case .confirmed: return match.winnerId == myId ? "Победа, подтверждён" : "Поражение, подтверждён"
        case .disputed:  return "Оспорен, не учитывается"
        case .proposed:  return match.awaitsResponse(from: myId) ? "Нужно ваше подтверждение" : "Ждём подтверждения партнёра"
        }
    }

    private func statusColor(_ match: Match) -> Color {
        switch match.status {
        case .confirmed: return AppColor.textSecondary
        case .disputed:  return AppColor.danger
        case .proposed:  return match.awaitsResponse(from: myId) ? AppColor.warning : AppColor.textSecondary
        }
    }

    @ViewBuilder
    private var addMatchSection: some View {
        if meeting.canAddMatch {
            Button("Добавить ещё один матч") { open(ordinal: meeting.nextOrdinal) }
                .buttonStyle(SecondaryButtonStyle())
            Text("Сыграли ещё раз? У каждого матча свой счёт и своё подтверждение — все подтверждённые попадут в статистику.")
                .font(.footnote)
                .foregroundColor(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        } else if meeting.limitReached {
            Text("За одну встречу можно внести не больше \(MatchIds.maxPerMeeting) матчей.")
                .font(.footnote)
                .foregroundColor(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        } else {
            Text("Новый матч можно добавить, когда по предыдущему будет принято решение.")
                .font(.footnote)
                .foregroundColor(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Действия

    private func open(ordinal: Int) {
        openedOrdinal = ordinal
        showMatch = true
    }

    private func load() {
        MatchService.shared.fetchMeetingMatches(requestId: requestId) { loaded in
            meeting = loaded
            isLoading = false
            onChanged(loaded)
            openPendingIfRequested()
        }
    }

    /// Переход по уведомлению: сразу к матчу, который ждёт ответа
    private func openPendingIfRequested() {
        guard autoOpenPending, !didAutoOpen,
              let pending = meeting.firstAwaitingResponse(from: myId) else { return }
        didAutoOpen = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            open(ordinal: pending.ordinal)
        }
    }
}

// MARK: - Список матчей игрока
struct MatchHistoryList: View {
    @ObservedObject var store: PlayerMatchesStore
    let userId: String

    @State private var filter = MatchHistoryFilter()

    var body: some View {
        let all = historyMatches()

        VStack(alignment: .leading, spacing: AppSpacing.m) {
            if store.isLoading && !store.hasLoaded {
                ProgressView().frame(maxWidth: .infinity).padding(.top, AppSpacing.xl)
            } else if all.isEmpty {
                ProfilePlaceholder(
                    icon: "list.clipboard",
                    title: "Пока нет матчей",
                    subtitle: "Здесь появятся матчи, счёт которых подтвердили оба игрока"
                )
            } else {
                let shown = filter.apply(to: all)

                if all.count >= FilterThreshold.matches {
                    MatchHistoryFilterBar(filter: $filter, matches: all, shownCount: shown.count)
                }

                if shown.isEmpty {
                    FilterEmptyResult { withAnimation { filter.reset() } }
                } else {
                    list(shown)
                }
            }
        }
    }

    /// Подтверждённые матчи в виде, удобном для фильтров (имена подставляются по мере загрузки)
    private func historyMatches() -> [HistoryMatch] {
        store.countedMatches.compactMap { match in
            guard let opponentId = match.opponentId(of: userId),
                  let perspective = match.perspective(of: userId) else { return nil }
            return HistoryMatch(
                id: match.id,
                date: match.playedAt,
                opponentId: opponentId,
                opponentName: store.name(of: opponentId),
                won: perspective.won,
                gamesWon: perspective.gamesWon,
                gamesLost: perspective.gamesLost,
                ordinal: match.ordinal
            )
        }
    }

    private func list(_ matches: [HistoryMatch]) -> some View {
        LazyVStack(spacing: AppSpacing.m) {
            if filter.sort.isByDate {
                ForEach(HistoryBuckets.groupedByMonth(matches, date: { $0.date })) { group in
                    HistoryMonthHeader(month: group.month, count: group.items.count)
                    ForEach(group.items) { row($0) }
                }
            } else {
                ForEach(matches) { row($0) }
            }
        }
    }

    private func row(_ match: HistoryMatch) -> some View {
        NavigationLink {
            PlayerProfileView(userId: match.opponentId)
        } label: {
            HStack(spacing: AppSpacing.m) {
                InitialsAvatar(fullName: match.opponentName, userId: match.opponentId, size: AppSize.avatarSmall)

                VStack(alignment: .leading, spacing: 2) {
                    Text(match.opponentName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColor.textPrimary)
                        .lineLimit(1)
                    Text(AppDate.dayShort(match.date))
                        .font(.caption)
                        .foregroundColor(AppColor.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(match.gamesWon) : \(match.gamesLost)")
                        .font(.headline.monospacedDigit())
                        .foregroundColor(match.won ? AppColor.success : AppColor.textPrimary)
                    Text(match.won ? "победа" : "поражение")
                        .font(.caption)
                        .foregroundColor(AppColor.textSecondary)
                }
            }
            .padding(AppSpacing.m)
            .background(AppColor.cardBackground)
            .cornerRadius(AppRadius.medium)
        }
        .buttonStyle(.plain)
    }
}
