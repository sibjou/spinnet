import SwiftUI
import FirebaseFirestore

struct BookedGameDetailView: View {
    let game: [String: Any]
    @ObservedObject var authService: AuthService
    @ObservedObject var sparringService: SparringService
    @Binding var isPresented: Bool
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var clarification: MeetingClarification? = nil
    @State private var isLoadingClarification = false
    @State private var showClarification = false
    @State private var partnerName: String = "Загрузка..."
    @State private var partnerSkill: String = ""
    @State private var partnerCity: String = ""
    @State private var isLoadingPartner = true
    @State private var isProcessing = false
    @State private var showCancelConfirm = false
    @State private var showReviewForm = false
    @State private var alreadyReviewed = false

    var formattedDate: String {
        guard let timestamp = game["date"] as? Timestamp else { return "Дата не указана" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy, EEEE"
        return formatter.string(from: timestamp.dateValue())
    }

    var partnerId: String? {
        guard let userId = authService.currentUserId else { return nil }
        let authorId   = game["userId"]   as? String
        let bookedById = game["bookedBy"] as? String
        return authorId == userId ? bookedById : authorId
    }

    var myRole: String {
        game["userId"] as? String == authService.currentUserId ? "автор заявки" : "забронировал"
    }

    // MARK: - Статус игры

    var gameStatus: String {
        game["status"] as? String ?? ""
    }

    // Игра завершена или истекла — в истории, действия недоступны
    var isFinished: Bool {
        gameStatus == "completed" || gameStatus == "expired"
    }

    // Игра ещё предстоит — можно уточнять и отменять
    var isUpcoming: Bool {
        gameStatus == "booked" || gameStatus == "in_progress"
    }

    var body: some View {
        NavigationStack {
            List {

                // MARK: - Партнёр
                Section("С кем играете") {
                    if isLoadingPartner {
                        HStack {
                            ProgressView()
                            Text("Загрузка...").foregroundColor(.secondary)
                        }
                    } else if let id = partnerId {
                        NavigationLink {
                            PlayerProfileView(userId: id)
                        } label: {
                            HStack(spacing: 12) {
                                InitialsAvatar(fullName: partnerName, userId: id, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(partnerName).fontWeight(.semibold)
                                    Text("\(partnerSkill) • \(partnerCity)")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                // MARK: - Детали встречи
                Section("Детали встречи") {
                    Label(formattedDate, systemImage: "calendar")
                    Label(game["timeSlot"] as? String ?? "", systemImage: "clock")
                    GameLocationLabel(
                        city:     game["city"]     as? String ?? "",
                        location: game["location"] as? String ?? ""
                    )
                    Button {
                        let city     = game["city"]     as? String ?? ""
                        let location = game["location"] as? String ?? ""
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
                }

                // MARK: - Роль
                Section("Ваша роль") {
                    Label("Вы: \(myRole)", systemImage: "person.fill.checkmark")
                        .foregroundColor(.secondary)
                }

                // MARK: - Уточнения (только для предстоящих игр)
                if isUpcoming {
                    Section {
                        Button {
                            openClarification()
                        } label: {
                            HStack {
                                Label("Уточнить детали встречи", systemImage: "checklist")
                                Spacer()
                                if isLoadingClarification {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isLoadingClarification)
                    }
                }

                // MARK: - Оценить игрока (только для завершённых)
                if gameStatus == "completed" {
                    Section {
                        if alreadyReviewed {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Вы оценили эту игру")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Button {
                                showReviewForm = true
                            } label: {
                                Label("Оценить игрока", systemImage: "star.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                    } footer: {
                        Text("Ваш отзыв поможет другим игрокам найти достойного партнёра")
                            .font(.caption)
                    }
                }

                // MARK: - Отмена (только для предстоящих игр)
                if isUpcoming {
                    Section {
                        Button("Отменить участие", role: .destructive) {
                            showCancelConfirm = true
                        }
                        .disabled(isProcessing)
                    } footer: {
                        Text("Заявка вернётся в общую ленту")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isFinished ? "Завершённая игра" : "Предстоящая игра")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") { isPresented = false }
                }
            }
            .alert("Отменить участие?", isPresented: $showCancelConfirm) {
                Button("Нет", role: .cancel) {}
                Button("Отменить", role: .destructive) { cancelAction() }
            } message: {
                Text("Заявка вернётся в общую ленту")
            }
            .sheet(isPresented: $showClarification) {
                if let clar = clarification {
                    NavigationStack {
                        ClarificationDetailView(
                            clarification: clar,
                            authService: authService
                        )
                    }
                }
            }
            .sheet(isPresented: $showReviewForm) {
                if let id = partnerId,
                   let requestId = game["documentId"] as? String {
                    ReviewFormView(
                        toUserId: id,
                        toUserName: partnerName,
                        sparringRequestId: requestId,
                        authService: authService
                    )
                    .onDisappear {
                        checkIfReviewed()
                    }
                }
            }
            .onAppear {
                loadPartnerInfo()
                checkIfReviewed()
            }
        }
    }

    // MARK: - Загрузка партнёра

    private func loadPartnerInfo() {
        guard let id = partnerId, !id.isEmpty else {
            partnerName = "Партнёр не найден"
            isLoadingPartner = false
            return
        }

        UserService.shared.fetchUser(id: id) { data in
            if let data = data {
                self.partnerName  = UserService.fullName(from: data)
                self.partnerSkill = data["skillLevel"] as? String ?? ""
                self.partnerCity  = data["city"]       as? String ?? ""
            } else {
                self.partnerName = "Пользователь удалён"
            }
            self.isLoadingPartner = false
        }
    }

    // MARK: - Открыть / создать уточнение

    private func openClarification() {
        guard let requestId = game["documentId"] as? String else { return }
        isLoadingClarification = true

        // Ищем существующий диалог
        ClarificationService().findActiveClarification(forRequestId: requestId) { existing in
                    self.isLoadingClarification = false

                    if let clar = existing {
                        self.appState.clarificationToOpen = clar
                        self.appState.selectedTab = .chat
                        self.isPresented = false
                    } else {
                        // Создаём draft с правильными ролями
                        guard let myUserId = self.authService.currentUserId,
                              let profile = self.authService.userProfile else { return }

                        let myUserName = "\(profile.firstName) \(profile.lastName)"
                            .trimmingCharacters(in: .whitespaces)

                        let realAuthorId   = self.game["userId"] as? String ?? ""
                        let realBookedById = self.game["bookedBy"] as? String ?? ""

                        let fn = self.game["authorFirstName"] as? String ?? ""
                        let ln = self.game["authorLastName"]  as? String ?? ""
                        let realAuthorName = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)

                        let isMeAuthor = (myUserId == realAuthorId)

                        let bookedByName: String
                        if isMeAuthor {
                            bookedByName = self.partnerName
                        } else {
                            bookedByName = myUserName
                        }

                        let draftData: [String: Any] = [
                            "sparringRequestId": requestId,
                            "authorId":          realAuthorId,
                            "authorName":        realAuthorName.isEmpty ? "Автор" : realAuthorName,
                            "bookedById":        realBookedById,
                            "bookedByName":      bookedByName.isEmpty ? "Партнёр" : bookedByName,
                            "sparringDate":      self.game["date"]     as? Timestamp ?? Timestamp(),
                            "sparringTimeSlot":  self.game["timeSlot"] as? String ?? "",
                            "sparringCity":      self.game["city"]     as? String ?? "",
                            "sparringLocation":  self.game["location"] as? String ?? "",
                            "status":            "active",
                            "createdAt":         Timestamp(),
                            "updatedAt":         Timestamp()
                        ]

                        let draftId = "draft_\(requestId)"
                        if let clar = MeetingClarification(id: draftId, data: draftData) {
                            self.appState.clarificationToOpen = clar
                            self.appState.selectedTab = .chat
                            self.isPresented = false
                        }
                    }
        }
    }

    // MARK: - Отмена бронирования

    private func cancelAction() {
        guard let requestId = game["documentId"] as? String,
              let userId    = authService.currentUserId else { return }
        isProcessing = true

        sparringService.cancelBooking(requestId: requestId) { success in
            isProcessing = false
            if success {
                sparringService.loadAll(userId: userId)
                isPresented = false
            }
        }
    }

    private func checkIfReviewed() {
        guard let userId = authService.currentUserId,
              let requestId = game["documentId"] as? String else { return }

        ReviewService().hasReviewed(
            fromUserId: userId,
            sparringRequestId: requestId
        ) { reviewed in
            alreadyReviewed = reviewed
        }
    }
}
