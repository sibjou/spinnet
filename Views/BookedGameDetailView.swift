import SwiftUI
import FirebaseFirestore

struct BookedGameDetailView: View {
    let game: [String: Any]
    @ObservedObject var authService: AuthService
    @ObservedObject var sparringService: SparringService
    @Binding var isPresented: Bool
    /// Открыть сразу экран счёта (переход по уведомлению о счёте)
    var autoOpenMatch: Bool = false
    /// Открыть сразу форму отзыва (переход по уведомлению «Оцените игру»)
    var autoOpenReview: Bool = false
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var isLoadingClarification = false
    @State private var partnerName: String = "Загрузка..."
    @State private var partnerSkill: String = ""
    @State private var partnerCity: String = ""
    @State private var isLoadingPartner = true
    @State private var isProcessing = false
    @State private var showCancelConfirm = false
    @State private var showReviewForm = false
    @State private var alreadyReviewed = false
    @State private var reviewStatusLoaded = false
    @State private var meeting = MeetingMatches([])
    @State private var showMatch = false
    @State private var didAutoOpenMatch = false
    @State private var didAutoOpenReview = false
    @State private var partnerAllowsClarifications = true
    @State private var showMessagesOffAlert = false

    var formattedDate: String {
        guard let timestamp = game["date"] as? Timestamp else { return "Дата не указана" }
        return AppDate.fullWithWeekday(timestamp.dateValue())
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

    // MARK: - Счёт матча

    var iAmAuthor: Bool {
        game["userId"] as? String == authService.currentUserId
    }

    var gameStart: Date? {
        guard let timestamp = game["date"] as? Timestamp,
              let slot = game["timeSlot"] as? String else { return nil }
        return GameSlot.startDate(day: timestamp.dateValue(), slot: slot)
    }

    /// Момент окончания игры
    var gameEnd: Date? {
        guard let timestamp = game["date"] as? Timestamp,
              let slot = game["timeSlot"] as? String,
              let range = GameSlot.minutes(from: slot) else { return nil }
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: timestamp.dateValue())
        return calendar.date(byAdding: .minute, value: range.end, to: midnight)
    }

    /// Время игры вышло. Считаем по часам, а не по статусу в базе: статус обновляется
    /// только когда кто-то откроет приложение, и до этого кнопки итогов не появлялись.
    var gameEnded: Bool {
        if gameStatus == "completed" { return true }
        guard let end = gameEnd else { return false }
        return end <= Date()
    }

    /// Оценить партнёра можно, когда игра закончилась и партнёр известен
    var canRate: Bool {
        guard let id = partnerId, !id.isEmpty else { return false }
        return ["booked", "in_progress", "completed"].contains(gameStatus) && gameEnded
    }

    /// Счёт можно вносить, когда партнёр есть и игра уже началась
    var canEnterScore: Bool {
        guard let id = partnerId, !id.isEmpty,
              ["booked", "in_progress", "completed"].contains(gameStatus),
              let start = gameStart else { return false }
        return start <= Date()
    }

    private var matchRowTitle: String {
        guard let myId = authService.currentUserId else { return "Внести счёт" }
        switch meeting.summary(for: myId) {
        case .none:                        return "Внести счёт"
        case .needsYourAnswer:             return "Подтвердить счёт"
        case .waitingForPartner:           return "Счёт внесён, ждём партнёра"
        case .single:                      return "Счёт матча"
        case .several:                     return "Счёт матчей (\(meeting.confirmed.count))"
        case .disputedOnly:                return "Счёт оспорен"
        }
    }

    /// Справа в строке: итог подтверждённых матчей
    private var matchRowTrailing: String? {
        guard let myId = authService.currentUserId else { return nil }
        switch meeting.summary(for: myId) {
        case .single(let won, let lost, _):  return "\(won):\(lost)"
        case .several(let won, let lost):    return "\(won):\(lost)"
        default:                             return nil
        }
    }

    private var matchFooterText: String {
        if meeting.isEmpty {
            return "Любой из вас может внести результат по партиям. Второй игрок получит уведомление и подтвердит счёт. Сыграли несколько матчей — вносите каждый отдельно."
        }
        return "В статистику и рейтинг идут только подтверждённые матчи."
    }

    // Игра ещё предстоит — можно уточнять и отменять
    var isUpcoming: Bool {
        (gameStatus == "booked" || gameStatus == "in_progress") && !gameEnded
    }

    private var cancelTitle: String { iAmAuthor ? "Отменить игру?" : "Отказаться от игры?" }
    private var cancelButtonTitle: String { iAmAuthor ? "Отменить игру" : "Отказаться от игры" }
    private var cancelConfirmTitle: String { iAmAuthor ? "Отменить" : "Отказаться" }

    private var cancelMessage: String {
        iAmAuthor
            ? "Игра будет отменена, заявка закроется. Партнёр получит уведомление"
            : "Заявка автора вернётся в общую ленту. Он получит уведомление"
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
                        // Если место выбрано на карте, метка ставится точно в эту точку
                        MapsOpener.open(
                            name:      game["location"] as? String ?? "",
                            city:      game["city"]     as? String ?? "",
                            latitude:  game["locationLatitude"]  as? Double,
                            longitude: game["locationLongitude"] as? Double
                        )
                    } label: {
                        Label("Открыть в картах", systemImage: "map")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }

                // MARK: - Счёт матча
                if canEnterScore || !meeting.isEmpty {
                    Section {
                        Button {
                            showMatch = true
                        } label: {
                            HStack {
                                Label(matchRowTitle, systemImage: "list.clipboard")
                                Spacer()
                                if let trailing = matchRowTrailing {
                                    Text(trailing)
                                        .font(.subheadline.weight(.bold).monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } footer: {
                        Text(matchFooterText)
                            .font(.caption)
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
                        .disabled(isLoadingClarification || isLoadingPartner)
                    }
                }

                // MARK: - Оценить игрока (как только игра закончилась)
                if canRate {
                    Section {
                        if alreadyReviewed {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AppColor.primary)
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
                    } header: {
                        Text("Итоги встречи")
                    } footer: {
                        Text("Ваш отзыв поможет другим игрокам найти достойного партнёра")
                            .font(.caption)
                    }
                }

                // MARK: - Отмена (только для предстоящих игр)
                if isUpcoming {
                    Section {
                        Button(cancelButtonTitle, role: .destructive) {
                            showCancelConfirm = true
                        }
                        .disabled(isProcessing)
                    } footer: {
                        Text(cancelMessage)
                            .font(.caption)
                    }
                }
            }
            .connectionNotice()
            .navigationTitle(isFinished || gameEnded ? "Завершённая игра" : "Предстоящая игра")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") { isPresented = false }
                }
            }
            .alert(cancelTitle, isPresented: $showCancelConfirm) {
                Button("Нет", role: .cancel) {}
                Button(cancelConfirmTitle, role: .destructive) { cancelAction() }
            } message: {
                Text(cancelMessage)
            }
            .alert("Сообщения недоступны", isPresented: $showMessagesOffAlert) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text("\(partnerName) отключил(а) сообщения от других игроков.")
            }
            .navigationDestination(isPresented: $showMatch) {
                if let id = partnerId, let requestId = game["documentId"] as? String,
                   let myId = authService.currentUserId {
                    MeetingMatchesView(
                        requestId: requestId,
                        myId: myId,
                        myName: authService.userProfile?.fullName ?? "Вы",
                        partnerId: id,
                        partnerName: partnerName,
                        iAmAuthor: iAmAuthor,
                        autoOpenPending: autoOpenMatch,
                        onChanged: { updated in meeting = updated }
                    )
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
                loadMatch()
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
                self.partnerAllowsClarifications = PrivacySettings(userData: data).allowClarifications
            } else {
                self.partnerName = "Пользователь удалён"
            }
            self.isLoadingPartner = false
            self.openMatchIfRequested()
            self.openReviewIfRequested()
        }
    }

    // MARK: - Счёт: загрузка и автоматическое открытие

    private func loadMatch() {
        guard let requestId = game["documentId"] as? String else { return }
        MatchService.shared.fetchMeetingMatches(requestId: requestId) { found in
            self.meeting = found
        }
    }

    /// Форма отзыва открывается, когда известен партнёр и ясно, что отзыв ещё не оставлен
    private func openReviewIfRequested() {
        guard autoOpenReview, !didAutoOpenReview,
              !isLoadingPartner, reviewStatusLoaded,
              canRate, !alreadyReviewed else { return }
        didAutoOpenReview = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showReviewForm = true
        }
    }

    private func openMatchIfRequested() {
        guard autoOpenMatch, !didAutoOpenMatch,
              let id = partnerId, !id.isEmpty else { return }
        didAutoOpenMatch = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showMatch = true
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
                        // Партнёр отключил сообщения — новый диалог не создаём
                        guard self.partnerAllowsClarifications else {
                            self.showMessagesOffAlert = true
                            return
                        }

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
                        var draft = draftData
                        if let latitude = self.game["locationLatitude"] as? Double,
                           let longitude = self.game["locationLongitude"] as? Double {
                            draft["sparringLatitude"] = latitude
                            draft["sparringLongitude"] = longitude
                        }

                        let draftId = "draft_\(requestId)"
                        if let clar = MeetingClarification(id: draftId, data: draft) {
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
            reviewStatusLoaded = true
            openReviewIfRequested()
        }
    }
}
