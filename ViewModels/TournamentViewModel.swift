import Foundation
import Combine
import FirebaseFirestore

/// Турнир в списке: id нужен, чтобы строки не путались при обновлении
struct TournamentItem: Identifiable {
    let id: String
    let data: [String: Any]
}

final class TournamentViewModel: ObservableObject {

    @Published var displayedTournaments: [TournamentItem] = []
    @Published var isLoading = false
    @Published var hasLoadedOnce = false   // первая загрузка завершилась (успешно или нет)

    // Город — серверный фильтр
    // Свободные места и статус — клиентские
    @Published var filterCity     = "Все города"   { didSet { if oldValue != filterCity { loadFromServer() } } }
    @Published var filterOnlyFree = false           { didSet { applyClientFilters() } }

    var hasActiveFilters: Bool {
        filterCity != "Все города" || filterOnlyFree
    }

    /// Сколько ближайших турниров показывает список
    static let maxShown = 100

    private let db = Firestore.firestore()
    private var allTournaments: [TournamentItem] = []

    /// Номер последней загрузки: ответ более старой загрузки (например, до смены города) игнорируется
    private var generation = 0

    /// Обновление по жесту «потянуть вниз»: ждёт ответ сервера, но не дольше `RefreshWait.timeout`.
    /// Без этого при плохой сети жест висел, пока Firestore сам не сдавался (около десяти секунд).
    func refresh() async {
        let began = Date()
        Perf.event("турниры: жест обновления начался")
        await RefreshWait.wait { finish in
            loadFromServer(completion: finish)
        }
        // Чтобы обновление не мигало, если ответ пришёл мгновенно
        try? await Task.sleep(nanoseconds: 350_000_000)
        Perf.event("турниры: жест обновления закончился через \(Int(Date().timeIntervalSince(began) * 1000)) мс")
    }

    func loadFromServer(completion: (() -> Void)? = nil) {
        generation += 1
        let current = generation
        isLoading = true
        Perf.begin("турниры: запрос")

        var base: Query = db.collection("tournaments")
            .whereField("status", in: ["upcoming", "in_progress"])

        if filterCity != "Все города" {
            base = base.whereField("city", isEqualTo: filterCity)
        }

        // Если составной индекс (status + date) ещё не создан, запрос с сортировкой падает.
        // Тогда читаем без сортировки и сортируем сами — список не должен пустеть из-за индекса.
        let unsorted = base
        // Ближайшие турниры: список не должен читать всю базу, когда турниров станет много.
        // Дальние находятся фильтром по городу (он серверный).
        let sorted = base.order(by: "date", descending: false).limit(to: Self.maxShown)

        // Сначала то, что уже лежит в памяти телефона: список появляется сразу, а не после ответа сервера.
        // Пустой ответ из памяти ничего не значит (там может просто не быть этих данных) — его пропускаем.
        if !hasLoadedOnce {
            sorted.getDocuments(source: .cache) { [weak self] snapshot, _ in
                let items = Self.items(from: snapshot)
                DispatchQueue.main.async {
                    guard let self, current == self.generation, !self.hasLoadedOnce, !items.isEmpty else { return }
                    self.hasLoadedOnce = true
                    self.allTournaments = items
                    self.applyClientFilters()
                    Perf.mark("турниры: показаны из памяти телефона")
                }
            }
        }

        sorted.getDocuments { [weak self] snapshot, error in
            if error != nil {
                debugLog("TournamentViewModel: запрос с сортировкой не выполнен (\(error?.localizedDescription ?? "?")), читаю без неё")
                unsorted.getDocuments { [weak self] snapshot, error in
                    self?.finishLoading(snapshot: snapshot, error: error, sortByDate: true,
                                        generation: current, completion: completion)
                }
            } else {
                self?.finishLoading(snapshot: snapshot, error: error, sortByDate: false,
                                    generation: current, completion: completion)
            }
        }
    }

    private static func items(from snapshot: QuerySnapshot?) -> [TournamentItem] {
        snapshot?.documents.map { doc in
            var data = doc.data()
            data["documentId"] = doc.documentID
            return TournamentItem(id: doc.documentID, data: data)
        } ?? []
    }

    private func finishLoading(snapshot: QuerySnapshot?,
                               error: Error?,
                               sortByDate: Bool,
                               generation current: Int,
                               completion: (() -> Void)?) {
        // Разбор документов — до перехода в главный поток: сами снимки туда не передаём
        var items = Self.items(from: snapshot)
        if sortByDate {
            items.sort {
                let a = ($0.data["date"] as? Timestamp)?.dateValue() ?? .distantFuture
                let b = ($1.data["date"] as? Timestamp)?.dateValue() ?? .distantFuture
                return a < b
            }
        }
        let loaded = items
        DispatchQueue.main.async {
            defer { completion?() }
            // Пока шёл запрос, город сменили или запустили новую загрузку: этот ответ устарел
            guard current == self.generation else { return }
            self.isLoading = false
            self.hasLoadedOnce = true
            Perf.end("турниры: запрос")
            Perf.mark("турниры: список загружен")
            if let error = error {
                debugLog("TournamentViewModel error: \(error.localizedDescription)")
                return
            }
            self.allTournaments = loaded
            self.applyClientFilters()
        }
    }

    private func applyClientFilters() {
        displayedTournaments = allTournaments.filter { item in
            if filterOnlyFree {
                let count = (item.data["participants"] as? [String])?.count ?? 0
                let max   = item.data["maxParticipants"] as? Int ?? 0
                if max > 0 && count >= max { return false }
            }
            return true
        }
    }

    func resetFilters() {
        filterOnlyFree = false
        filterCity     = "Все города"  // последним — запустит loadFromServer()
    }
}
