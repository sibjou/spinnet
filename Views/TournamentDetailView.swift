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
    @State private var showRemoveConfirm = false
    @State private var showLeaveConfirm = false
    @State private var removeParticipantId = ""
    @State private var removeParticipantName = ""
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
        return AppDate.fullWithWeekday(timestamp.dateValue())
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
                
                GameLocationLabel(
                    city: tournament["city"] as? String ?? "",
                    location: tournament["location"] as? String ?? ""
                )

                Button {
                    let city     = tournament["city"]     as? String ?? ""
                    let location = tournament["location"] as? String ?? ""
                    let query    = "\(city) \(location)".trimmingCharacters(in: .whitespaces)
                    let encoded  = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "maps://?q=\(encoded)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Открыть в картах", systemImage: "map")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                // Профиль организатора открывается так же, как профиль любого игрока
                if let organizerId = tournament["organizerId"] as? String,
                   !organizerId.isEmpty, organizerId != authService.currentUserId {
                    NavigationLink {
                        PlayerProfileView(userId: organizerId)
                    } label: {
                        Label("Организатор: \(tournament["organizerName"] as? String ?? "")",
                              systemImage: "person.badge.shield.checkmark")
                    }
                } else {
                    Label("Организатор: \(tournament["organizerName"] as? String ?? "")",
                          systemImage: "person.badge.shield.checkmark")
                }
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
            
            // Список участников
            Section("Участники (\(participantCount))") {
                if isLoadingNames {
                    ProgressView()
                } else if participantNames.isEmpty {
                    Text("Пока никто не записался")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(participantNames, id: \.id) { participant in
                        VStack(alignment: .leading, spacing: 8) {
                            participantRow(participant)

                            // Кнопки управления (только организатор незавершённого турнира)
                            if isOrganizer && tournament["status"] as? String != "completed" {
                                HStack(spacing: 12) {
                                    if confirmedParticipants.contains(participant.id) {
                                        Button(action: {
                                            unconfirmAction(userId: participant.id)
                                        }) {
                                            Label("Отменить", systemImage: "arrow.uturn.backward")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.borderless)
                                        .foregroundColor(.orange)
                                        .disabled(isProcessing)
                                    } else {
                                        Button(action: {
                                            confirmAction(userId: participant.id)
                                        }) {
                                            Label("Подтвердить", systemImage: "checkmark")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.borderless)
                                        .foregroundColor(AppColor.primary)
                                        .disabled(isProcessing)
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        removeParticipantId = participant.id
                                        removeParticipantName = participant.name
                                        showRemoveConfirm = true
                                    }) {
                                        Label("Удалить", systemImage: "xmark")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundColor(.red)
                                    .disabled(isProcessing)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            // Завершение турнира (только организатор)
            // Кнопки для организатора
            if isOrganizer && tournament["status"] as? String != "completed" {
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
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomAction }
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
        
        .alert("Удалить участника?", isPresented: $showRemoveConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                removeAction(userId: removeParticipantId)
            }
        } message: {
            Text("Удалить \(removeParticipantName) из турнира?")
        }
        
        .alert("Отменить участие?", isPresented: $showLeaveConfirm) {
            Button("Остаться", role: .cancel) {}
            Button("Отменить участие", role: .destructive) { leaveAction() }
        } message: {
            Text("Ваше место освободится для других игроков.")
        }

        .alert("Турнир", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Нижняя панель: главное действие всегда на виду
    // Раньше кнопка «Записаться» стояла посреди списка и уходила за край экрана.

    @ViewBuilder
    private var bottomAction: some View {
        if !isOrganizer && tournament["status"] as? String != "completed" {
            VStack(spacing: 0) {
                Divider()
                Group {
                    if isJoined {
                        VStack(spacing: AppSpacing.s) {
                            Label("Вы записаны на турнир", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(AppColor.success)
                            Button("Отменить участие", role: .destructive) {
                                showLeaveConfirm = true
                            }
                            .font(.subheadline)
                            .disabled(isProcessing)
                        }
                    } else if isFull {
                        Label("Все места заняты", systemImage: "person.3.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppColor.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: AppSize.buttonHeight)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
                    } else {
                        Button(action: joinAction) {
                            if isProcessing {
                                ProgressView().tint(.white)
                            } else {
                                Text("Записаться на турнир")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isProcessing)
                    }
                }
                .padding(.horizontal, AppSpacing.l)
                .padding(.vertical, AppSpacing.m)
            }
            .background(.bar)
        }
    }

    // MARK: - Строка участника
    // Бейдж «Подтверждён» стоит внутри ссылки, поэтому стрелка у всех строк на одном месте

    private func participantRow(_ participant: (id: String, name: String)) -> some View {
        let isMe = participant.id == authService.currentUserId
        let content = HStack(spacing: AppSpacing.s) {
            InitialsAvatar(fullName: participant.name, userId: participant.id, size: 28)
            Text(participant.name)
                .foregroundColor(.primary)
            if isMe {
                Text("(вы)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: AppSpacing.s)
            if confirmedParticipants.contains(participant.id) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Подтверждён")
                        .font(.caption)
                }
                .foregroundColor(AppColor.primary)
            }
        }
        return Group {
            if isMe {
                content
            } else {
                NavigationLink {
                    PlayerProfileView(userId: participant.id)
                } label: {
                    content
                }
            }
        }
    }

    // MARK: - Отменить подтверждение
        private func unconfirmAction(userId: String) {
            guard let docId = tournament["documentId"] as? String else { return }
            isProcessing = true
            
            tournamentService.unconfirmParticipant(tournamentId: docId, userId: userId) { success in
                if success {
                    alertMessage = "Подтверждение отменено"
                    showAlert = true
                    reloadTournament()
                } else {
                    isProcessing = false
                }
            }
        }
        
        // MARK: - Удалить участника
        private func removeAction(userId: String) {
            guard let docId = tournament["documentId"] as? String else { return }
            isProcessing = true
            
            tournamentService.removeParticipant(tournamentId: docId, userId: userId) { success in
                if success {
                    alertMessage = "Участник удалён из турнира"
                    showAlert = true
                    reloadTournament()
                } else {
                    isProcessing = false
                }
            }
        }
    
    // MARK: - Загружаю имена участников из базы
    private func loadParticipantNames() {
        guard let participants = tournament["participants"] as? [String] else {
            isLoadingNames = false
            return
        }
        
        UserService.shared.fetchNames(ids: participants) { namesById in
            let names = participants.compactMap { id -> (id: String, name: String)? in
                guard let name = namesById[id] else { return nil }
                return (id: id, name: name)
            }

            // Текущий пользователь всегда сверху списка
            let myId = self.authService.currentUserId
            self.participantNames = names.sorted { a, b in
                if a.id == myId { return true }   // я — первый
                if b.id == myId { return false }
                return a.name < b.name            // остальные по алфавиту
            }
            self.isLoadingNames = false
        }
    }
    
    // MARK: - Обновляю данные турнира после действий
    // Загружаю свежие данные из Firestore чтобы экран сразу обновился
    private func reloadTournament() {
        guard let docId = tournament["documentId"] as? String else { return }
        
        tournamentService.fetchTournament(id: docId) { fresh in
            if var data = fresh {
                // Сохраняю имя организатора (его нет в Firestore, мы его подгрузили)
                data["organizerName"] = self.tournament["organizerName"]
                self.tournament = data
                self.loadParticipantNames()
            }
            self.isProcessing = false
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
        }
    }
}
