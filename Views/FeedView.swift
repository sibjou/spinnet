import SwiftUI
import Combine

struct FeedView: View {
    @ObservedObject var authService: AuthService
    @EnvironmentObject private var appState: AppState

    @State private var requestForDetails: SparringRequest? = nil
    @State private var authorForProfile: String? = nil
    @StateObject private var viewModel: FeedViewModel
    @State private var selectedSegment = 0
    @State private var showCityPicker = false
    @State private var showCreateRequest = false
    @State private var showBookingConfirm = false
    @State private var requestToBook: SparringRequest? = nil

    /// Раз в минуту игры, которые закончились, уходят из ленты, а «Сегодня» и «Завтра» остаются верными
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// Первое содержимое ленты (список или пустой экран) появилось на экране
    private let onContentShown: () -> Void

    init(authService: AuthService, onContentShown: @escaping () -> Void = {}) {
        self.authService = authService
        self.onContentShown = onContentShown
        Perf.mark("лента: экран создаётся")
        let name = "\(authService.userProfile?.firstName ?? "") \(authService.userProfile?.lastName ?? "")"
            .trimmingCharacters(in: .whitespaces)
        _viewModel = StateObject(wrappedValue:
            FeedViewModel(
                currentUserId:   authService.currentUserId ?? "",
                currentUserName: name,
                homeCity:        authService.userProfile?.city ?? "",
                myLevel:         authService.userProfile?.skillLevel ?? ""
            )
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if selectedSegment == 0 {
                    FeedFilterBar(
                        city: viewModel.filterCity,
                        day: $viewModel.filterDay,
                        onlyMyLevel: $viewModel.onlyMyLevel,
                        canFilterByLevel: LevelMatch.index(authService.userProfile?.skillLevel ?? "") != nil,
                        onCityTap: { showCityPicker = true }
                    )
                }
                content
            }
            .tabBarInset()
            .navigationTitle("Лента")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Сегмент по центру
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $selectedSegment) {
                        Text("Спарринги").tag(0)
                        Text("Тренеры").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                // Хват и стиль — справа, только для спаррингов
                if selectedSegment == 0 {
                    filterToolbar
                }
            }
            .sheet(isPresented: $showCityPicker) {
                CityPickerView(
                    selectedCity: Binding(
                        get: { viewModel.filterCity },
                        set: { viewModel.selectCity($0) }
                    ),
                    isPresented: $showCityPicker,
                    allCitiesTitle: FeedCity.all
                )
            }
            .sheet(isPresented: $showCreateRequest) {
                CreateRequestView(authService: authService)
            }
            .sheet(item: $requestForDetails) { request in
                RequestDetailView(
                    request: request,
                    authService: authService,
                    onBook: {
                        // Окно подробностей закрывается: диалог подтверждения показываем, когда оно уйдёт
                        requestToBook = request
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showBookingConfirm = true }
                    }
                )
            }
            .sheet(item: Binding(
                get: { authorForProfile.map { IDWrapper(id: $0) } },
                set: { authorForProfile = $0?.id }
            )) { wrapper in
                NavigationStack {
                    PlayerProfileView(userId: wrapper.id)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Закрыть") { authorForProfile = nil }
                            }
                        }
                }
            }
            .sheet(item: $viewModel.bookedRequest) { request in
                BookingSuccessView(request: request, authService: authService)
                    .environmentObject(appState)
            }
            .alert("Бронирование", isPresented: Binding(
                get: { viewModel.bookingError != nil },
                set: { if !$0 { viewModel.bookingError = nil } }
            )) {
                Button("OK") { viewModel.bookingError = nil }
            } message: {
                Text(viewModel.bookingError ?? "")
            }
            .confirmationDialog(
                bookingTitle,
                isPresented: $showBookingConfirm,
                titleVisibility: .visible
            ) {
                Button("Записаться") {
                    if let req = requestToBook { viewModel.book(request: req) }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                if let req = requestToBook {
                    Text("\(bookingWhen(req))\n\(bookingWhere(req))")
                }
            }
            .task {
                Perf.mark("лента: загрузка начинается")
                // Профиль мог загрузиться позже создания экрана: город и уровень берём свежие
                viewModel.profileDidChange(city: authService.userProfile?.city ?? "",
                                           level: authService.userProfile?.skillLevel ?? "")
                // Лента и блокировки грузятся одновременно, а не по очереди.
                // Список блокировок с прошлого раза подставляется сразу, свежий придёт с сервера
                if BlockService.shared.restoreCache() { viewModel.blocksDidLoad() }
                viewModel.startListening()
                BlockService.shared.loadBlocks { viewModel.blocksDidLoad() }
                Perf.mark("лента: загрузка запущена")
            }
            .onAppear { Perf.mark("лента: экран появился") }
            .onDisappear { viewModel.stopListening() }
            .onChange(of: authService.userProfile?.city ?? "") { _, _ in syncProfile() }
            .onChange(of: authService.userProfile?.skillLevel ?? "") { _, _ in syncProfile() }
            .onReceive(minuteTimer) { _ in viewModel.applyClientFilters() }
            .refreshable { await viewModel.refresh() }
        }
    }

    private func syncProfile() {
        viewModel.profileDidChange(city: authService.userProfile?.city ?? "",
                                   level: authService.userProfile?.skillLevel ?? "")
    }

    // MARK: - Содержимое

    @ViewBuilder
    private var content: some View {
        if selectedSegment == 0 {
            // MARK: Спарринги
            if !viewModel.isFirstLoadDone {
                RefreshableState { LoadingStateView(title: "Ищем заявки…") }
            } else if viewModel.displayedRequests.isEmpty {
                // В обёртке, чтобы пустую ленту тоже можно было потянуть вниз
                RefreshableState { emptyState }
                    .onAppear { onContentShown() }
            } else {
                requestsList
            }
        } else {
            // MARK: Тренеры (заглушка)
            EmptyStateView(
                art: .symbol("person.2.fill"),
                title: "Тренеры — скоро",
                message: "Здесь появятся тренеры и секции вашего города. Раздел в разработке."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Список заявок

    private var requestsList: some View {
        let now = Date()
        let sections = FeedGrouping.sections(viewModel.displayedRequests, day: { $0.date })
        return ScrollView {
            LazyVStack(spacing: AppSpacing.m, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { request in
                            RequestCardView(
                                request: request,
                                showsDay: false,
                                isBooking: viewModel.bookingRequestId == request.id,
                                onTapCard: { requestForDetails = request },
                                onTapAuthor: { authorForProfile = request.userId },
                                onBook: {
                                    requestToBook = request
                                    showBookingConfirm = true
                                }
                            )
                        }
                    } header: {
                        dayHeader(FeedGrouping.title(for: section.day, now: now))
                    }
                }

                if viewModel.hasMore {
                    Button("Показать ещё") { viewModel.loadMore() }
                        .font(.subheadline)
                        .foregroundColor(AppColor.primary)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.l)
        }
        .onAppear {
            Perf.mark("лента: список на экране")
            onContentShown()
        }
    }

    private func dayHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(AppColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppSpacing.s)
            .background(AppColor.background)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Подтверждение брони

    private var bookingTitle: String {
        guard let req = requestToBook else { return "Записаться на игру?" }
        let name = req.authorFirstName.isEmpty ? req.authorFullName : req.authorFirstName
        return name.isEmpty ? "Записаться на игру?" : "Сыграть с игроком \(name)?"
    }

    private func bookingWhen(_ req: SparringRequest) -> String {
        let day = RequestTiming.dayWord(for: req.date) ?? AppDate.dayLong(req.date)
        return "\(day), \(req.timeSlot)"
    }

    private func bookingWhere(_ req: SparringRequest) -> String {
        [req.city, req.location].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - Пустое состояние

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.hasActiveFilters {
            EmptyStateView(
                art: .symbol("line.3.horizontal.decrease.circle"),
                title: "Ничего не нашлось",
                message: "Попробуйте другой день или сбросьте фильтры.",
                primaryTitle: "Сбросить фильтры",
                primaryAction: { viewModel.resetFilters() }
            )
        } else if viewModel.filterCity != FeedCity.all {
            EmptyStateView(
                art: .tableTennis,
                title: "Заявок пока нет",
                message: "В городе «\(viewModel.filterCity)» ещё никто не искал партнёра. Создайте заявку первым — её увидят другие игроки.",
                primaryTitle: "Создать заявку",
                primaryAction: { showCreateRequest = true },
                secondaryTitle: "Показать все города",
                secondaryAction: { viewModel.selectCity(FeedCity.all) }
            )
        } else {
            EmptyStateView(
                art: .tableTennis,
                title: "Заявок пока нет",
                message: "Создайте заявку — её увидят другие игроки.",
                primaryTitle: "Создать заявку",
                primaryAction: { showCreateRequest = true }
            )
        }
    }

    // MARK: - Хват и стиль

    @ToolbarContentBuilder
    private var filterToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Picker("Хват", selection: $viewModel.filterGrip) {
                    Text("Любой хват").tag("Любой хват")
                    Text("Шейкхолд").tag("Шейкхолд")
                    Text("Пенхолд").tag("Пенхолд")
                }
                Picker("Стиль", selection: $viewModel.filterStyle) {
                    Text("Любой стиль").tag("Любой стиль")
                    Text("Нападающий").tag("Нападающий")
                    Text("Защитник").tag("Защитник")
                    Text("Комбинированный").tag("Комбинированный")
                }
                if viewModel.hasActiveFilters {
                    Divider()
                    Button("Сбросить фильтры", role: .destructive) {
                        viewModel.resetFilters()
                    }
                }
            } label: {
                Image(systemName: viewModel.hasMenuFilters
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .foregroundColor(viewModel.hasMenuFilters ? AppColor.primary : .primary)
            }
            .accessibilityLabel("Хват и стиль игры")
        }
    }

    struct IDWrapper: Identifiable {
        let id: String
    }
}
