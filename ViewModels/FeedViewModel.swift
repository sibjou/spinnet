import Foundation
import Combine
import FirebaseFirestore

final class FeedViewModel: ObservableObject {

    @Published var displayedRequests: [SparringRequest] = []
    @Published var isLoading = false
    @Published var hasLoadedOnce = false   // первая загрузка завершилась (успешно или нет)
    @Published private(set) var blocksReady = false   // список блокировок известен (с телефона или с сервера)

    /// Ленту можно показывать: заявки пришли и понятно, чьи из них скрыть
    var isFirstLoadDone: Bool { hasLoadedOnce && blocksReady }
    @Published var hasMore = false
    @Published var bookingError: String? = nil

    /// Заявка, которую только что забронировали: по ней открывается экран «Вы записаны»
    @Published var bookedRequest: SparringRequest? = nil
    /// Заявка, которая бронируется прямо сейчас: повторное нажатие не создаёт вторую бронь
    @Published private(set) var bookingRequestId: String? = nil

    // MARK: Фильтры
    // Город выбирается один раз: по умолчанию лента показывает город из профиля.
    // День и «Подходит мне» — быстрые фильтры над лентой, хват и стиль — в меню.

    /// Город ленты. Меняется через `selectCity` или сам, вместе с городом в профиле
    @Published private(set) var filterCity: String
    @Published var filterDay: FeedDay = .any            { didSet { clientFilterChanged() } }
    @Published var onlyMyLevel = false                  { didSet { clientFilterChanged() } }
    @Published var filterGrip  = "Любой хват"           { didSet { clientFilterChanged() } }
    @Published var filterStyle = "Любой стиль"          { didSet { clientFilterChanged() } }

    /// Включён хоть один фильтр, кроме города (город — выбор, а не фильтр: он сохраняется)
    var hasActiveFilters: Bool {
        filterDay != .any || onlyMyLevel || hasMenuFilters
    }

    /// Хват или стиль: лежат в меню, значок меню подсвечивается
    var hasMenuFilters: Bool {
        filterGrip != "Любой хват" || filterStyle != "Любой стиль"
    }

    /// Город из профиля (подставляется, пока человек сам не выбрал другой)
    private(set) var homeCity: String
    /// Уровень игры из профиля: по нему работает «Подходит мне»
    private(set) var myLevel: String

    private static let pageSize = 20
    /// Сколько заявок лента догружает сама, если фильтры скрыли всё, что пришло
    private static let autoLoadLimit = 100

    private let db = Firestore.firestore()
    private let defaults: UserDefaults
    private let currentUserId: String
    private let currentUserName: String
    private var savedCity: String?
    private var listener: ListenerRegistration?
    private var serverRequests: [SparringRequest] = []
    private var pageLimit = FeedViewModel.pageSize

    /// Номер подписки: ответ более старой подписки (до смены города) игнорируется
    private var listenerGeneration = 0

    /// Составной индекс (статус + дата) на сервере ещё не создан — читаем по времени создания.
    /// Помнится до конца запуска, чтобы не повторять заведомо неудачный запрос.
    private static var dateOrderUnavailable = false

    init(currentUserId: String,
         currentUserName: String = "",
         homeCity: String = "",
         myLevel: String = "",
         defaults: UserDefaults = .standard) {
        self.currentUserId   = currentUserId
        self.currentUserName = currentUserName
        self.homeCity        = homeCity
        self.myLevel         = myLevel
        self.defaults        = defaults
        let saved = defaults.string(forKey: FeedCity.storageKey(userId: currentUserId))
        self.savedCity   = saved
        self.filterCity  = FeedCity.effective(home: homeCity, saved: saved)
        Perf.mark("лента: модель создана")
    }

    deinit {
        listener?.remove()
        giveUpWork?.cancel()
    }

    // MARK: - Город

    /// Человек выбрал город в ленте. Свой город — это «следовать за профилем», другой запоминается.
    func selectCity(_ chosen: String) {
        savedCity = FeedCity.savedValue(chosen: chosen, home: homeCity)
        let key = FeedCity.storageKey(userId: currentUserId)
        if let savedCity {
            defaults.set(savedCity, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        applyCity(FeedCity.effective(home: homeCity, saved: savedCity))
    }

    /// Профиль загрузился или изменился: лента следует за городом из профиля, если город не выбран вручную
    func profileDidChange(city: String, level: String) {
        let levelChanged = level != myLevel
        myLevel = level
        if city != homeCity {
            homeCity = city
            applyCity(FeedCity.effective(home: homeCity, saved: savedCity))
        } else if levelChanged {
            applyClientFilters()
        }
    }

    private func applyCity(_ city: String) {
        guard city != filterCity else { return }
        filterCity = city
        // Пока лента не запущена, подписка начнётся сама; перезапуск нужен только работающей
        if listener != nil { startListening() }
    }

    // MARK: - Блокировки

    /// Список блокировок известен или обновился: пересчитываем, что показывать
    func blocksDidLoad() {
        blocksReady = true
        Perf.mark("лента: блокировки готовы")
        applyClientFilters()
    }

    /// Вызывается один раз, когда пришёл первый ответ после (пере)подписки
    private var firstSnapshotHandler: (() -> Void)?

    // MARK: - Загрузка

    /// Обновление по жесту «потянуть вниз»: завершается, когда лента обновилась, но не позже
    /// `RefreshWait.timeout`. Без ограничения при плохой сети жест висел бы, пока сервер не сдастся.
    func refresh() async {
        let began = Date()
        Perf.event("лента: жест обновления начался")
        await RefreshWait.wait { finish in
            startListening(onFirstSnapshot: finish)
        }
        // Чтобы обновление не мигало, если ответ пришёл мгновенно из кэша
        try? await Task.sleep(nanoseconds: 350_000_000)
        Perf.event("лента: жест обновления закончился через \(Int(Date().timeIntervalSince(began) * 1000)) мс")
    }

    /// Запрос заявок. Ближайшие по дате, начиная с сегодняшнего дня; без индекса — по времени создания.
    private func makeQuery(sortedByDate: Bool, limit: Int) -> Query {
        var query: Query = db.collection("sparring_requests")
            .whereField("status", isEqualTo: "active")

        if filterCity != FeedCity.all {
            query = query.whereField("city", isEqualTo: filterCity)
        }

        if sortedByDate {
            // Дальше фильтр «игра ещё не закончилась» дорабатывает приложение: тут отсекаются прошлые дни
            let today = Calendar.current.startOfDay(for: Date())
            return query
                .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: today))
                .order(by: "date", descending: false)
                .limit(to: limit)
        }
        return query
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
    }

    /// Подписка на ленту. По умолчанию начинает с первой страницы.
    func startListening(resetPaging: Bool = true, onFirstSnapshot: (() -> Void)? = nil) {
        listener?.remove()
        // Предыдущее обновление не дождалось ответа — отпускаем его, чтобы оно не зависло
        firstSnapshotHandler?()
        firstSnapshotHandler = onFirstSnapshot
        isLoading = true
        if resetPaging { pageLimit = Self.pageSize }

        listenerGeneration += 1
        let generation = listenerGeneration
        let sortedByDate = !Self.dateOrderUnavailable
        let limit = pageLimit
        let query = makeQuery(sortedByDate: sortedByDate, limit: limit)

        Perf.begin("лента: запрос заявок")
        scheduleGiveUp()
        listener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            // Копия до перехода в главный поток: сами снимки туда не передаём
            let fromCache = snapshot?.metadata.isFromCache
            let isEmpty = snapshot?.documents.isEmpty ?? true
            DispatchQueue.main.async {
                // Ответ устаревшей подписки (город сменили, пока шёл запрос) не нужен
                guard generation == self.listenerGeneration else { return }

                // Нет составного индекса: тот же запрос без сортировки по дате, сортировка на телефоне
                if error != nil, sortedByDate {
                    debugLog("FeedViewModel: запрос с сортировкой по дате не выполнен (\(error?.localizedDescription ?? "?")), читаю по времени создания")
                    Self.dateOrderUnavailable = true
                    let handler = self.firstSnapshotHandler
                    self.firstSnapshotHandler = nil
                    self.startListening(resetPaging: false, onFirstSnapshot: handler)
                    return
                }

                self.isLoading = false
                // Различаем ответ из памяти телефона и ответ сервера — от этого зависит, сколько ждать
                if let fromCache {
                    Perf.mark(fromCache ? "лента: ответ из кэша телефона" : "лента: ответ сервера")
                }
                // Пустая копия на телефоне (первый запуск, переустановка) — не «заявок нет»:
                // ждём сервер, а человек пока видит анимацию загрузки
                if FeedLoadRule.countsAsLoaded(fromCache: fromCache, isEmpty: isEmpty, hasError: error != nil) {
                    self.markLoaded()
                    Perf.end("лента: запрос заявок")
                    Perf.mark("лента: первый ответ")
                } else {
                    Perf.mark("лента: копия на телефоне пустая, ждём сервер")
                }
                defer {
                    self.firstSnapshotHandler?()
                    self.firstSnapshotHandler = nil
                }
                if let error = error {
                    debugLog("FeedViewModel error: \(error.localizedDescription)")
                    return
                }

                let documents = snapshot?.documents ?? []
                // Если сервер вернул полную страницу — вероятно, есть ещё
                self.hasMore = documents.count >= limit

                // Блокировки применяются в applyClientFilters, чтобы лента
                // обновлялась и когда список блокировок загрузился позже
                self.serverRequests = documents.compactMap { doc in
                    guard let req = SparringRequest(id: doc.documentID, data: doc.data()),
                          req.userId != self.currentUserId
                    else { return nil }
                    return req
                }
                self.applyClientFilters()
                Perf.mark("лента: данные применены, заявок на экране: \(self.displayedRequests.count)")
            }
        }
    }

    /// Подгрузить следующую порцию заявок
    func loadMore() {
        guard hasMore, !isLoading else { return }
        pageLimit += Self.pageSize
        startListening(resetPaging: false)
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        listenerGeneration += 1
        giveUpWork?.cancel()
        giveUpWork = nil
        // Обновление, которое ждало ответ, не должно висеть
        firstSnapshotHandler?()
        firstSnapshotHandler = nil
    }

    // MARK: - Ожидание сервера после пустой копии

    private var giveUpWork: DispatchWorkItem?

    private func markLoaded() {
        hasLoadedOnce = true
        giveUpWork?.cancel()
        giveUpWork = nil
    }

    /// Если сервер так и не ответил (нет сети), через `FeedLoadRule.giveUpAfter` секунд
    /// показываем то, что есть, чтобы анимация не крутилась вечно
    private func scheduleGiveUp() {
        giveUpWork?.cancel()
        giveUpWork = nil
        guard !hasLoadedOnce else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hasLoadedOnce else { return }
            self.hasLoadedOnce = true
            Perf.mark("лента: сервер не ответил за \(Int(FeedLoadRule.giveUpAfter)) с, показываем что есть")
        }
        giveUpWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + FeedLoadRule.giveUpAfter, execute: work)
    }

    // MARK: - Что показывать

    private func clientFilterChanged() {
        applyClientFilters()
    }

    /// Пересчёт ленты: скрыть заблокированных и прошедшие игры, применить фильтры, упорядочить по времени.
    /// Вызывается и раз в минуту — игры, которые закончились, исчезают сами.
    func applyClientFilters(now: Date = Date()) {
        // Пока не знаем, кого скрывать, ничего не показываем — иначе на секунду мелькнули бы чужие заявки
        guard blocksReady else {
            displayedRequests = []
            return
        }
        let blockedIds = BlockService.shared.allBlockedIds
        let calendar = Calendar.current
        let visible = serverRequests.filter { req in
            guard !blockedIds.contains(req.userId) else { return false }
            guard RequestTiming.isUpcoming(day: req.date, slot: req.timeSlot, now: now, calendar: calendar) else { return false }
            guard filterDay.matches(req.date, now: now, calendar: calendar) else { return false }
            if onlyMyLevel,
               !LevelMatch.fits(myLevel: myLevel, authorLevel: req.authorSkillLevel, desiredLevel: req.desiredLevel) {
                return false
            }
            if filterGrip  != "Любой хват"  && req.authorGrip      != filterGrip  { return false }
            if filterStyle != "Любой стиль" && req.authorPlayStyle != filterStyle { return false }
            return true
        }
        displayedRequests = FeedOrder.sorted(visible,
                                             day: { $0.date },
                                             slot: { $0.timeSlot },
                                             createdAt: { $0.createdAt },
                                             calendar: calendar)
        loadMoreIfEmpty()
    }

    /// Фильтры скрыли всё, что пришло, а на сервере есть ещё: догружаем (но не бесконечно)
    private func loadMoreIfEmpty() {
        guard displayedRequests.isEmpty, hasMore, !isLoading, pageLimit < Self.autoLoadLimit else { return }
        DispatchQueue.main.async { [weak self] in self?.loadMore() }
    }

    func resetFilters() {
        filterDay   = .any
        onlyMyLevel = false
        filterGrip  = "Любой хват"
        filterStyle = "Любой стиль"
    }

    // MARK: - Бронирование

    private static let alreadyBookedCode = 409

    /// Бронирование в транзакции: если заявку успели забронировать или удалить
    /// с момента загрузки ленты, запись не перезапишется.
    func book(request: SparringRequest) {
        guard request.userId != currentUserId, bookingRequestId == nil else { return }

        // Без сети транзакция не пройдёт: объясняем сразу, а не ждём ответ, которого не будет
        guard ConnectionMonitor.shared.isOnline else {
            bookingError = ConnectionRule.actionRejected
            return
        }

        // Защита: нельзя забронировать заявку заблокированного (в обе стороны)
        if BlockService.shared.isBlocked(request.userId) {
            bookingError = "Этот игрок недоступен"
            return
        }

        // Игра закончилась, пока человек смотрел ленту
        guard RequestTiming.isUpcoming(day: request.date, slot: request.timeSlot) else {
            bookingError = "Время этой игры уже прошло"
            applyClientFilters()
            return
        }

        let ref = db.collection("sparring_requests").document(request.id)
        let userId = currentUserId
        bookingRequestId = request.id

        db.runTransaction({ transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            guard snapshot.data()?["status"] as? String == "active" else {
                errorPointer?.pointee = NSError(
                    domain: "Spinnet",
                    code: FeedViewModel.alreadyBookedCode,
                    userInfo: [NSLocalizedDescriptionKey: "Заявка уже недоступна"]
                )
                return nil
            }

            transaction.updateData([
                "status":   "booked",
                "bookedBy": userId,
                "bookedAt": Timestamp()
            ], forDocument: ref)
            return nil
        }) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.bookingRequestId = nil

                if let error = error as NSError? {
                    if error.domain == "Spinnet", error.code == FeedViewModel.alreadyBookedCode {
                        self.bookingError = "Эту заявку уже забронировали или удалили. Лента обновлена"
                    } else {
                        self.bookingError = "Не удалось забронировать: \(error.localizedDescription)"
                    }
                    return
                }

                // Заявка ушла из ленты сразу, не дожидаясь ответа подписки
                self.serverRequests.removeAll { $0.id == request.id }
                self.applyClientFilters()
                self.bookedRequest = request

                // Уведомление автору заявки — его игру забронировали
                NotificationService.shared.saveAndPush(
                    userId: request.userId,
                    type: .requestBooked,
                    title: "Вашу заявку забронировали 🏓",
                    body: "\(self.currentUserName.isEmpty ? "Игрок" : self.currentUserName) хочет сыграть с вами \(self.formatDate(request.date)) в \(request.timeSlot)",
                    targetType: "game",
                    targetId: request.id,
                    actorId: userId,
                    actorName: self.currentUserName
                )

                // Планируем локальные напоминания (на устройстве забронировавшего)
                NotificationService.shared.scheduleGameReminder(
                    sparringRequestId: request.id,
                    partnerName: request.authorFullName,
                    gameDate: request.date,
                    timeSlot: request.timeSlot
                )
                NotificationService.shared.scheduleMatchReminder(
                    sparringRequestId: request.id,
                    partnerName: request.authorFullName,
                    gameDate: request.date,
                    timeSlot: request.timeSlot
                )
                NotificationService.shared.scheduleReviewReminder(
                    sparringRequestId: request.id,
                    partnerName: request.authorFullName,
                    gameDate: request.date,
                    timeSlot: request.timeSlot
                )
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        AppDate.dayLong(date)
    }
}
