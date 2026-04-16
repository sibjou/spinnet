import SwiftUI
import FirebaseFirestore

// MARK: - ProfileView
// Экран профиля пользователя
// Структура: аватарка + имя сверху, кнопка редактирования,
// три вкладки: Мои игры | Участие в турнирах | Мои турниры
struct ProfileView: View {
    @ObservedObject var authService: AuthService
    @StateObject private var sparringService = SparringService()
    @StateObject private var tournamentService = TournamentService()
    
    @State private var editingRequestId: String? = nil
    @State private var userData: [String: Any] = [:]
    @State private var isLoadingProfile = true
    @State private var selectedTab = 0  // 0 = Мои игры, 1 = Участие, 2 = Мои турниры
    @State private var showSettings = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Шапка профиля
                    profileHeader
                    
                    // Кнопка редактирования профиля
                    Button(action: {}) {
                        Text("Редактировать профиль")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal)
                    
                    // MARK: - Три вкладки
                    tabSelector
                    
                    // MARK: - Содержимое выбранной вкладки
                    tabContent
                }
            }
            .navigationTitle("Профиль")
            .toolbar {
                // Кнопка настроек (три полоски) в правом верхнем углу
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(authService: authService)
            }
            .sheet(item: Binding(
                get: { editingRequestId.map { IdentifiableString(id: $0) } },
                set: { editingRequestId = $0?.id }
            )) { wrapper in
                EditRequestView(
                    requestId: wrapper.id,
                    isPresented: Binding(
                        get: { editingRequestId != nil },
                        set: { if !$0 { editingRequestId = nil } }
                    ),
                    onUpdate: { loadAllData() }
                )
            }
            .onAppear { loadAllData() }
           
            
        }
    }
    
    // MARK: - Шапка профиля (аватарка, имя, статистика)
    private var profileHeader: some View {
        HStack(spacing: 16) {
            // Аватарка
            Image(systemName: "person.circle.fill")
                .font(.system(size: 70))
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 4) {
                // Имя и фамилия
                Text("\(userData["firstName"] as? String ?? "") \(userData["lastName"] as? String ?? "")")
                    .font(.title2.bold())
                
                // Город и уровень
                Text("\(userData["skillLevel"] as? String ?? "") • \(userData["city"] as? String ?? "")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Хват и стиль
                Text("\(userData["grip"] as? String ?? "") • \(userData["playStyle"] as? String ?? "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Статистика: игры и рейтинг
                HStack(spacing: 16) {
                    // Количество сыгранных игр
                    HStack(spacing: 4) {
                        Image(systemName: "sportscourt")
                            .font(.caption)
                        Text("\(sparringService.myCompletedGames.count) игр")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    
                    // Рейтинг (пока заглушка, позже подключим отзывы)
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("—")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: - Переключатель вкладок (три кнопки в ряд)
    private var tabSelector: some View {
        HStack(spacing: 0) {
            tabButton(title: "Спарринги", icon: "sportscourt", index: 0)
            tabButton(title: "Участвую", icon: "trophy", index: 1)
            tabButton(title: "Организую", icon: "crown", index: 2)
        }
        .padding(.horizontal)
    }

    // Одна кнопка вкладки
    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundColor(selectedTab == index ? .green : .secondary)
            // Подчёркивание активной вкладки
            .overlay(alignment: .bottom) {
                if selectedTab == index {
                    Rectangle()
                        .fill(Color.green)
                        .frame(height: 2)
                }
            }
        }
    }
    
    // MARK: - Содержимое вкладок
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            myGamesTab
        case 1:
            myTournamentsParticipationTab
        case 2:
            myCreatedTournamentsTab
        default:
            EmptyView()
        }
    }
    
    // MARK: - Вкладка "Мои игры"
    private var myGamesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Активные заявки
            if !sparringService.myActiveRequests.isEmpty {
                sectionHeader("Активные заявки", color: .green)
                ForEach(sparringService.myActiveRequests.indices, id: \.self) { index in
                    gameCard(sparringService.myActiveRequests[index], status: "active")
                }
            }
            
            // Забронированные игры (ожидают встречи)
            if !sparringService.myBookedGames.isEmpty {
                sectionHeader("Предстоящие игры", color: .blue)
                ForEach(sparringService.myBookedGames.indices, id: \.self) { index in
                    gameCard(sparringService.myBookedGames[index], status: "booked")
                }
            }
            
            // История (завершённые)
            if !sparringService.myCompletedGames.isEmpty {
                sectionHeader("История игр", color: .gray)
                ForEach(sparringService.myCompletedGames.indices, id: \.self) { index in
                    gameCard(sparringService.myCompletedGames[index], status: "completed")
                }
            }
            
            // Если вообще ничего нет
            if sparringService.myActiveRequests.isEmpty &&
                sparringService.myBookedGames.isEmpty &&
                sparringService.myCompletedGames.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("Пока нет игр")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Вкладка "Участие в турнирах"
    private var myTournamentsParticipationTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            let myTournaments = tournamentService.tournaments.filter { tournament in
                guard let participants = tournament["participants"] as? [String],
                      let userId = authService.currentUserId else { return false }
                return participants.contains(userId)
            }
            
            if myTournaments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "trophy")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("Вы не записаны на турниры")
                        .foregroundColor(.secondary)
                }

                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ForEach(myTournaments.indices, id: \.self) { index in
                    tournamentCard(myTournaments[index])
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Вкладка "Мои созданные турниры"
    private var myCreatedTournamentsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            let createdTournaments = tournamentService.tournaments.filter { tournament in
                tournament["organizerId"] as? String == authService.currentUserId
            }
            
            if createdTournaments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "crown")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("Вы не создавали турниров")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ForEach(createdTournaments.indices, id: \.self) { index in
                    NavigationLink {
                        TournamentDetailView(
                            tournament: createdTournaments[index],
                            authService: authService,
                            tournamentService: tournamentService
                        )
                    } label: {
                        tournamentCard(createdTournaments[index])
                    }
                    .foregroundColor(.primary)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Компонент: заголовок секции
    private func sectionHeader(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.headline)
            .foregroundColor(color)
            .padding(.top, 8)
    }
    
    // MARK: - Компонент: карточка игры
    private func gameCard(_ game: [String: Any], status: String) -> some View {
        Button(action: {
            // Редактирование доступно только для активных своих заявок
            if status == "active", let docId = game["documentId"] as? String {
                editingRequestId = docId
            }
        }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(game["location"] as? String ?? "", systemImage: "mappin.circle.fill")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text(statusText(status))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusColor(status).opacity(0.15))
                        .foregroundColor(statusColor(status))
                        .cornerRadius(4)
                }
                
                Label(game["timeSlot"] as? String ?? "", systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let role = game["myRole"] as? String {
                    Text("Вы: \(role)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Подсказка что можно редактировать
                if status == "active" {
                    Text("Нажмите чтобы изменить")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .foregroundColor(.primary)
    }
    
    // MARK: - Компонент: карточка турнира
    private func tournamentCard(_ tournament: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tournament["title"] as? String ?? "")
                .font(.subheadline.bold())
            
            // Дата
            if let timestamp = tournament["date"] as? Timestamp {
                let formatter = DateFormatter()
                let _ = (formatter.locale = Locale(identifier: "ru_RU"))
                let _ = (formatter.dateFormat = "d MMMM yyyy")
                Label(formatter.string(from: timestamp.dateValue()), systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Label(tournament["location"] as? String ?? "", systemImage: "mappin.circle.fill")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Количество участников
            let count = (tournament["participants"] as? [String])?.count ?? 0
            let max = tournament["maxParticipants"] as? Int ?? 0
            Label("\(count)/\(max) участников", systemImage: "person.3.fill")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    // MARK: - Вспомогательные функции
    private func statusText(_ status: String) -> String {
        switch status {
        case "active": return "Активна"
        case "booked": return "Забронирована"
        case "completed": return "Завершена"
        default: return status
        }
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active": return .green
        case "booked": return .blue
        case "completed": return .gray
        default: return .secondary
        }
    }
    
    // MARK: - Загрузка всех данных профиля
    private func loadAllData() {
        guard let userId = authService.currentUserId else { return }
        
        // Загрузка данных профиля из Firestore
        Firestore.firestore().collection("users").document(userId).getDocument { doc, _ in
            DispatchQueue.main.async {
                isLoadingProfile = false
                userData = doc?.data() ?? [:]
            }
        }
        
        // Загрузка игр и турниров
        sparringService.loadAll(userId: userId)
        tournamentService.loadTournaments()
    }
    
    // Вспомогательная структура для sheet(item:)
    // Нужна чтобы передавать String как Identifiable
    struct IdentifiableString: Identifiable {
        let id: String
    }
}
