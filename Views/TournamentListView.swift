import SwiftUI
import FirebaseFirestore

// MARK: - TournamentListView
// Экран со списком предстоящих турниров
struct TournamentListView: View {
    @ObservedObject var authService: AuthService
    @StateObject private var tournamentService = TournamentService()
    
    @State private var showCreateTournament = false
    
    var body: some View {
        NavigationStack {
            Group {
                if tournamentService.isLoading {
                    ProgressView("Загрузка турниров...")
                } else if tournamentService.tournaments.isEmpty {
                    // Заглушка если турниров нет
                    VStack(spacing: 12) {
                        Image(systemName: "trophy")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("Пока нет турниров")
                            .foregroundColor(.secondary)
                        Text("Создайте первый турнир!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Список турниров
                    List(tournamentService.tournaments.indices, id: \.self) { index in
                        let tournament = tournamentService.tournaments[index]
                        
                        NavigationLink {
                            // При нажатии — переход к деталям турнира
                            TournamentDetailView(
                                tournament: tournament,
                                authService: authService,
                                tournamentService: tournamentService
                            )
                        } label: {
                            TournamentCardView(tournament: tournament, currentUserId: authService.currentUserId)
                        }
                    }
                }
            }
            .navigationTitle("Турниры")
            // Кнопка "+" для создания турнира
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showCreateTournament = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    }
                }
            }
            // Модальное окно создания турнира
            // .sheet — экран выезжает снизу (стандарт iOS)
            .sheet(isPresented: $showCreateTournament) {
                CreateTournamentView(
                    authService: authService,
                    tournamentService: tournamentService,
                    isPresented: $showCreateTournament
                )
            }
            .onAppear { tournamentService.loadTournaments() }
            .refreshable { tournamentService.loadTournaments() }
        }
    }
}

// MARK: - TournamentCardView
// Карточка турнира в списке
struct TournamentCardView: View {
    let tournament: [String: Any]
    let currentUserId: String?
    
    // Форматирование даты турнира
    var formattedDate: String {
        guard let timestamp = tournament["date"] as? Timestamp else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: timestamp.dateValue())
    }
    
    // Количество записавшихся
    var participantCount: Int {
        (tournament["participants"] as? [String])?.count ?? 0
    }
    
    // Максимум участников
    var maxParticipants: Int {
        tournament["maxParticipants"] as? Int ?? 0
    }
    
    // Записан ли текущий пользователь
    var isJoined: Bool {
        guard let userId = currentUserId,
              let participants = tournament["participants"] as? [String] else { return false }
        return participants.contains(userId)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Название турнира
            Text(tournament["title"] as? String ?? "")
                .font(.headline)
            
            // Организатор
            Label(tournament["organizerName"] as? String ?? "Организатор",
                  systemImage: "person.badge.shield.checkmark")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Дата и место
            Label(formattedDate, systemImage: "calendar")
                .font(.subheadline)
            
            // Время начала
            if let startTime = tournament["startTime"] as? String, !startTime.isEmpty {
                Label("в \(startTime)", systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Label(tournament["location"] as? String ?? "", systemImage: "mappin.circle.fill")
                .font(.subheadline)
            
            // Количество участников
            HStack {
                Label("\(participantCount)/\(maxParticipants) участников",
                      systemImage: "person.3.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Индикатор — записан или нет
                if isJoined {
                    Text("Вы записаны")
                        .font(.caption)
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
