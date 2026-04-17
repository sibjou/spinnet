import SwiftUI
import FirebaseFirestore

// MARK: - TournamentDetailView
// Детальная страница турнира
// Тут можно: записаться, отменить участие, посмотреть участников
// Организатор может: подтвердить явку, завершить турнир
struct TournamentDetailView: View {
    // Храню данные турнира как @State, чтобы обновлять их после действий
    @State private var tournament: [String: Any]
    @ObservedObject var authService: AuthService
    @ObservedObject var tournamentService: TournamentService
    
    @State private var showEdit = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var participantNames: [(id: String, name: String)] = []
    @State private var isLoadingNames = true
    @State private var isProcessing = false  // Блокирую кнопки пока идёт запрос
    
    // Принимаю начальные данные через init
    init(tournament: [String: Any], authService: AuthService, tournamentService: TournamentService) {
        _tournament = State(initialValue: tournament)
        self.authService = authService
        self.tournamentService = tournamentService
    }
    
    // Я — организатор этого турнира?
    var isOrganizer: Bool {
        tournament["organizerId"] as? String == authService.currentUserId
    }
    
    // Я записан на этот турнир?
    var isJoined: Bool {
        guard let userId = authService.currentUserId,
              let participants = tournament["participants"] as? [String] else { return false }
        return participants.contains(userId)
    }
    
    // Сколько участников записано
    var participantCount: Int {
        (tournament["participants"] as? [String])?.count ?? 0
    }
    
    var maxParticipants: Int {
        tournament["maxParticipants"] as? Int ?? 0
    }
    
    // Есть ли свободные места
    var isFull: Bool {
        participantCount >= maxParticipants
    }
    
    // Перевожу дату из Firestore в читаемый формат
    var formattedDate: String {
        guard let timestamp = tournament["date"] as? Timestamp else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy, EEEE"
        return formatter.string(from: timestamp.dateValue())
    }
    
    // Кто подтверждён организатором
    var confirmedParticipants: [String] {
        tournament["confirmedParticipants"] as? [String] ?? []
    }
    
    var body: some View {
        List {
            // Информация о турнире
            Section("Информация") {
                Label(formattedDate, systemImage: "calendar")
                
                // Время начала (если задано)
                if let startTime = tournament["startTime"] as? String, !startTime.isEmpty {
                    Label("Начало в \(startTime)", systemImage: "clock")
                }
                
                Label(tournament["location"] as? String ?? "", systemImage: "mappin.circle.fill")
                Label("Организатор: \(tournament["organizerName"] as? String ?? "")",
                      systemImage: "person.badge.shield.checkmark")
                Label("\(participantCount)/\(maxParticipants) участников",
                      systemImage: "person.3.fill")
            }
            
            // Описание турнира
            if let desc = tournament["description"] as? String, !desc.isEmpty {
                Section("Описание") {
                    Text(desc)
                        .foregroundColor(.secondary)
                }
            }
            
            // Кнопка записи/отмены (только если я не организатор)
            if !isOrganizer {
                Section {
                    if isJoined {
                        Button("Отменить участие", role: .destructive) {
                            leaveAction()
                        }
                        .disabled(isProcessing)
                    } else if isFull {
                        Text("Все места заняты")
                            .foregroundColor(.secondary)
                    } else {
                        Button(action: joinAction) {
                            if isProcessing {
                                ProgressView()
                            } else {
                                Text("Записаться на турнир")
                                    .frame(maxWidth: .infinity)
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(isProcessing)
                        .foregroundColor(.white)
                        .listRowBackground(Color.green)
                    }
                }
            }
            
            // Список участников
            Section("Участники (\(participantCount))") {
                if isLoadingNames {
                    ProgressView()
                } else if participantNames.isEmpty {
                    Text("Пока никто не записался")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(participantNames, id: \.id) { participant in
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.green)
                            Text(participant.name)
                            
                            Spacer()
                            
                            // Организатор видит кнопки подтверждения
                            if isOrganizer {
                                if confirmedParticipants.contains(participant.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Button("Подтвердить") {
                                        confirmAction(userId: participant.id)
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                    .disabled(isProcessing)
                                }
                            }
                        }
                    }
                }
            }
            
            // Завершение турнира (только организатор)
            // Кнопки для организатора
            if isOrganizer {
                Section {
                    Button(action: { showEdit = true }) {
                        Label("Редактировать турнир", systemImage: "pencil")
                    }
                    
                    Button("Завершить турнир", role: .destructive) {
                        completeAction()
                    }
                    .disabled(isProcessing)
                }
            }
        }
        .navigationTitle(tournament["title"] as? String ?? "Турнир")
        .onAppear { loadParticipantNames() }
        .sheet(isPresented: $showEdit) {
            EditTournamentView(
                tournamentId: tournament["documentId"] as? String ?? "",
                tournamentService: tournamentService,
                isPresented: $showEdit,
                onUpdate: {
                    // После редактирования — перезагружаем данные турнира
                    reloadTournament()
                }
            )
        }
        .alert("Турнир", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Загружаю имена участников из базы
    private func loadParticipantNames() {
        guard let participants = tournament["participants"] as? [String] else {
            isLoadingNames = false
            return
        }
        
        let db = Firestore.firestore()
        let group = DispatchGroup()
        var names: [(id: String, name: String)] = []
        
        for userId in participants {
            group.enter()
            db.collection("users").document(userId).getDocument { doc, _ in
                if let data = doc?.data() {
                    let name = "\(data["firstName"] ?? "") \(data["lastName"] ?? "")"
                    names.append((id: userId, name: name))
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            self.participantNames = names
            self.isLoadingNames = false
        }
    }
    
    // MARK: - Обновляю данные турнира после действий
    // Загружаю свежие данные из Firestore чтобы экран сразу обновился
    private func reloadTournament() {
        guard let docId = tournament["documentId"] as? String else { return }
        
        let db = Firestore.firestore()
        db.collection("tournaments").document(docId).getDocument { doc, _ in
            DispatchQueue.main.async {
                if var data = doc?.data() {
                    data["documentId"] = doc?.documentID
                    // Сохраняю имя организатора (его нет в Firestore, мы его подгрузили)
                    data["organizerName"] = self.tournament["organizerName"]
                    self.tournament = data
                    self.loadParticipantNames()
                }
                self.isProcessing = false
            }
        }
    }
    
    // MARK: - Записаться
    private func joinAction() {
        guard let userId = authService.currentUserId,
              let docId = tournament["documentId"] as? String else { return }
        isProcessing = true
        
        tournamentService.joinTournament(tournamentId: docId, userId: userId) { success in
            if success {
                alertMessage = "Вы записаны на турнир!"
                showAlert = true
                reloadTournament()  // Обновляю данные на экране
            } else {
                alertMessage = "Ошибка записи"
                showAlert = true
                isProcessing = false
            }
        }
    }
    
    // MARK: - Отменить участие
    private func leaveAction() {
        guard let userId = authService.currentUserId,
              let docId = tournament["documentId"] as? String else { return }
        isProcessing = true
        
        tournamentService.leaveTournament(tournamentId: docId, userId: userId) { success in
            if success {
                alertMessage = "Участие отменено"
                showAlert = true
                reloadTournament()
            } else {
                alertMessage = "Ошибка"
                showAlert = true
                isProcessing = false
            }
        }
    }
    
    // MARK: - Подтвердить участника (организатор)
    private func confirmAction(userId: String) {
        guard let docId = tournament["documentId"] as? String else { return }
        isProcessing = true
        
        tournamentService.confirmParticipant(tournamentId: docId, userId: userId) { success in
            if success {
                alertMessage = "Участник подтверждён"
                showAlert = true
                reloadTournament()
            } else {
                alertMessage = "Ошибка"
                showAlert = true
                isProcessing = false
            }
        }
    }
    
    // MARK: - Завершить турнир
    private func completeAction() {
        guard let docId = tournament["documentId"] as? String else { return }
        isProcessing = true
        
        tournamentService.completeTournament(tournamentId: docId) { success in
            alertMessage = success ? "Турнир завершён" : "Ошибка"
            showAlert = true
            isProcessing = false
            tournamentService.loadTournaments()
        }
    }
}
