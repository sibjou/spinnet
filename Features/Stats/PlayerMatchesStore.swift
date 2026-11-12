import Foundation
import Combine

// MARK: - PlayerMatchesStore
// Загружает матчи одного игрока и считает по ним статистику.
// Один экземпляр на экран профиля: вкладки «Статистика» и «Матчи» делят одни данные.
final class PlayerMatchesStore: ObservableObject {

    typealias MatchLoader = (_ userId: String, _ completion: @escaping ([Match]) -> Void) -> Void
    typealias NameLoader  = (_ ids: [String], _ completion: @escaping ([String: String]) -> Void) -> Void

    @Published private(set) var matches: [Match] = [] {
        didSet { rebuildIndexes() }
    }
    @Published private(set) var stats: PlayerStats = .empty
    @Published private(set) var names: [String: String] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false

    /// Матчи по встречам: список игр показывает отметку счёта на каждой карточке,
    /// и искать матчи перебором по всему списку на каждую карточку было бы O(игры × матчи)
    private var matchesByRequest: [String: [Match]] = [:]

    private let loadMatches: MatchLoader
    private let loadNames: NameLoader

    /// Без параметров читает данные из Firestore; в тестах подставляются свои загрузчики
    init(loadMatches: MatchLoader? = nil, loadNames: NameLoader? = nil) {
        self.loadMatches = loadMatches ?? { userId, completion in
            MatchService.shared.fetchMatches(userId: userId, completion: completion)
        }
        self.loadNames = loadNames ?? { ids, completion in
            UserService.shared.fetchNames(ids: ids, completion: completion)
        }
    }

    /// Подтверждённые матчи, новые сверху (внутри одной встречи — последний внесённый выше).
    /// Считается один раз при загрузке: экран перерисовывается часто, а проверка счёта каждого матча не бесплатна.
    private(set) var countedMatches: [Match] = []

    private func rebuildIndexes() {
        matchesByRequest = Dictionary(grouping: matches, by: { $0.requestId })
        countedMatches = matches.filter { $0.isCounted }.sorted { first, second in
            first.playedAt != second.playedAt ? first.playedAt > second.playedAt : first.ordinal > second.ordinal
        }
    }

    /// Первый матч встречи
    func match(forRequest id: String) -> Match? {
        matches.first { $0.id == id }
    }

    /// Все матчи встречи
    func meetingMatches(forRequest id: String) -> MeetingMatches {
        MeetingMatches(matchesByRequest[id] ?? [])
    }

    /// `force` — перечитать даже если данные уже есть (например, при возврате на экран)
    func load(userId: String, force: Bool = false) {
        if isLoading { return }
        if hasLoaded && !force { return }
        isLoading = true

        loadMatches(userId) { [weak self] loaded in
            guard let self else { return }
            self.matches = loaded
            self.stats = StatsCalculator.compute(matches: loaded, userId: userId)
            self.isLoading = false
            self.hasLoaded = true
            self.loadMissingNames(for: userId)
        }
    }

    private func loadMissingNames(for userId: String) {
        let ids = Set(matches.compactMap { $0.opponentId(of: userId) }).filter { names[$0] == nil }
        guard !ids.isEmpty else { return }
        loadNames(Array(ids)) { [weak self] loaded in
            self?.names.merge(loaded) { _, new in new }
        }
    }

    func name(of userId: String) -> String {
        let name = names[userId] ?? ""
        return name.isEmpty ? "Игрок" : name
    }
}
