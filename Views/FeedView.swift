import SwiftUI

struct FeedView: View {
    @ObservedObject var authService: AuthService
    
    @State private var requestForDetails: SparringRequest? = nil
    @State private var authorForProfile: String? = nil
    @StateObject private var viewModel: FeedViewModel
    @State private var selectedSegment = 0
    @State private var showCityPicker = false
    @State private var showBookingConfirm = false
    @State private var requestToBook: SparringRequest? = nil

    init(authService: AuthService) {
        self.authService = authService
        let name = "\(authService.userProfile?.firstName ?? "") \(authService.userProfile?.lastName ?? "")"
            .trimmingCharacters(in: .whitespaces)
        _viewModel = StateObject(wrappedValue:
            FeedViewModel(
                currentUserId:   authService.currentUserId ?? "",
                currentUserName: name
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if selectedSegment == 0 {
                    // MARK: - Спарринги
                    if viewModel.isLoading && viewModel.displayedRequests.isEmpty {
                        ProgressView("Загрузка...")
                    } else if viewModel.displayedRequests.isEmpty {
                        emptyState
                    } else {
                        requestsList
                    }
                } else {
                    // MARK: - Тренеры (заглушка)
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "person.badge.clock")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("Тренеры — скоро")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Раздел находится в разработке")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
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

                // Фильтры справа — только для спаррингов
                if selectedSegment == 0 {
                    filterToolbar
                }
            }
            .sheet(isPresented: $showCityPicker) {
                CityPickerView(selectedCity: $viewModel.filterCity, isPresented: $showCityPicker)
            }
            .sheet(item: $requestForDetails) { request in
                RequestDetailView(
                    request: request,
                    authService: authService,
                    onBook: {
                        requestToBook = request
                        showBookingConfirm = true
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
            .alert("Бронирование", isPresented: Binding(
                get: { viewModel.bookingError != nil },
                set: { if !$0 { viewModel.bookingError = nil } }
            )) {
                Button("OK") { viewModel.bookingError = nil }
            } message: {
                Text(viewModel.bookingError ?? "")
            }
            .confirmationDialog(
                "Забронировать встречу с \(requestToBook?.authorFullName ?? "")?",
                isPresented: $showBookingConfirm,
                titleVisibility: .visible
            ) {
                Button("Забронировать") {
                    if let req = requestToBook { viewModel.book(request: req) }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                if let req = requestToBook {
                    Text("\(req.city) · \(req.timeSlot)")
                }
            }
            .task {
                BlockService.shared.loadBlocks {
                    viewModel.startListening()
                }
            }
            .onDisappear { viewModel.stopListening() }
            .refreshable { viewModel.startListening() }
        }
    }

    // MARK: - Список заявок

    private var requestsList: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.m) {
                ForEach(viewModel.displayedRequests) { request in
                    RequestCardView(
                        request: request,
                        isOwnRequest: false,
                        onTapCard: {
                            requestForDetails = request
                        },
                        onTapAuthor: {
                            authorForProfile = request.userId
                        },
                        onBook: {
                            requestToBook = request
                            showBookingConfirm = true
                        }
                    )
                }
            }
            .padding(AppSpacing.l)
        }
    }

    // MARK: - Пустое состояние

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sportscourt")
                .font(.system(size: 50))
                .foregroundColor(.gray)

            if viewModel.hasActiveFilters {
                Text("Нет заявок по выбранным фильтрам")
                    .foregroundColor(.secondary)
                Button("Сбросить фильтры") { viewModel.resetFilters() }
                    .foregroundColor(.green)
            } else {
                Text("Пока нет заявок")
                    .foregroundColor(.secondary)
                Text("Нажмите + чтобы создать первую")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Фильтры

    @ToolbarContentBuilder
    private var filterToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Menu("Уровень: \(viewModel.filterLevel)") {
                    Button("Все уровни")   { viewModel.filterLevel = "Все уровни" }
                    Button("Начинающий")   { viewModel.filterLevel = "Начинающий" }
                    Button("Любитель")     { viewModel.filterLevel = "Любитель" }
                    Button("Продвинутый")  { viewModel.filterLevel = "Продвинутый" }
                    Button("Профессионал") { viewModel.filterLevel = "Профессионал" }
                }
                Menu("Хват: \(viewModel.filterGrip)") {
                    Button("Любой хват") { viewModel.filterGrip = "Любой хват" }
                    Button("Шейкхолд")   { viewModel.filterGrip = "Шейкхолд" }
                    Button("Пенхолд")    { viewModel.filterGrip = "Пенхолд" }
                }
                Menu("Стиль: \(viewModel.filterStyle)") {
                    Button("Любой стиль")    { viewModel.filterStyle = "Любой стиль" }
                    Button("Нападающий")     { viewModel.filterStyle = "Нападающий" }
                    Button("Защитник")       { viewModel.filterStyle = "Защитник" }
                    Button("Комбинированный"){ viewModel.filterStyle = "Комбинированный" }
                }
                Button("Город: \(viewModel.filterCity)") { showCityPicker = true }

                if viewModel.hasActiveFilters {
                    Divider()
                    Button("Сбросить все фильтры", role: .destructive) {
                        viewModel.resetFilters()
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(viewModel.hasActiveFilters ? .green : .primary)
            }
        }
    }
    struct IDWrapper: Identifiable {
        let id: String
    }
}
