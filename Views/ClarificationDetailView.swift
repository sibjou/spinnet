import SwiftUI
import FirebaseFirestore

struct ClarificationDetailView: View {
    let clarification: MeetingClarification
    @ObservedObject var authService: AuthService
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var showDeleteConfirm = false
    @State private var actions: [MeetingAction] = []
    @State private var isLoading = true
    @State private var isProcessing = false
    @State private var showTimePicker = false
    @State private var showLocationPicker = false
    @StateObject private var clarificationService = ClarificationService()

    private let service = ClarificationService()
    private var currentUserId: String { authService.currentUserId ?? "" }
    private var currentUserName: String {
        let p = authService.userProfile
        return "\(p?.firstName ?? "") \(p?.lastName ?? "")".trimmingCharacters(in: .whitespaces)
    }
    // Это временный (draft) диалог, ещё не сохранён в Firestore?
    private var isDraft: Bool {
        clarification.id.hasPrefix("draft_")
    }

    // Реальный ID диалога — для draft это будет sparringRequestId
    @State private var realClarificationId: String? = nil
    
    // ID партнёра в диалоге — тот из участников, кто не я
    private var partnerId: String {
        clarification.authorId == currentUserId
            ? clarification.bookedById
            : clarification.authorId
    }

    // Состояние блокировки
    @State private var isBlocked = false
    @State private var showBlockConfirm = false

    // Последнее действие которое ожидает ответа от меня
    private var pendingFromPartner: MeetingAction? {
        actions.last { $0.status == .pending && $0.fromUserId != currentUserId }
    }

    // Я уже отправил действие которое ждёт ответа?
    private var myActionPending: Bool {
        actions.last { $0.status == .pending && $0.fromUserId == currentUserId } != nil
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Шапка встречи
            meetingHeader

            Divider()

            // MARK: - История действий (пузыри)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if isLoading {
                            ProgressView().padding(.top, 40)
                        } else if actions.isEmpty {
                            emptyState
                        } else {
                            ForEach(actions) { action in
                                actionBubble(action)
                                    .id(action.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: actions.count) { _, _ in
                    if let last = actions.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // MARK: - Кнопки действий снизу
            actionButtons
        }
        .navigationTitle(clarification.partnerName(currentUserId: currentUserId))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if isBlocked {
                        Button {
                            unblockPartner()
                        } label: {
                            Label("Разблокировать", systemImage: "person.crop.circle.badge.checkmark")
                        }
                    } else {
                        Button(role: .destructive) {
                            showBlockConfirm = true
                        } label: {
                            Label("Заблокировать", systemImage: "person.crop.circle.badge.xmark")
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Удалить уточнение", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Удалить уточнение?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                let idToDelete = realClarificationId ?? clarification.id
                service.deleteClarification(id: idToDelete)
                appState.clarificationToOpen = nil   // ← очищаем кеш
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    dismiss()
                }
            }
        } message: {
            Text("Уточнение будет удалено для обоих участников")
        }
        .alert("Заблокировать игрока?", isPresented: $showBlockConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Заблокировать", role: .destructive) { blockPartner() }
        } message: {
            Text("Вы больше не увидите друг друга. Эта встреча будет отменена.")
        }
        .onAppear {
            loadActions()
            checkBlockStatus()
        }
        .onDisappear { service.stopActionsListener() }
        // Выбор времени
        .sheet(isPresented: $showTimePicker) { timePickerSheet }
        // Выбор места
        .sheet(isPresented: $showLocationPicker) { locationPickerSheet }
    }

    // MARK: - Шапка

    private var meetingHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text(clarification.sparringCity)
                        .fontWeight(.semibold)
                        .font(.subheadline)
                }
                Text(clarification.sparringLocation)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(clarification.sparringTimeSlot)
                    .fontWeight(.semibold)
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
    }

    // MARK: - Пузырь действия

    private func actionBubble(_ action: MeetingAction) -> some View {
        let isMe = action.fromUserId == currentUserId

        return HStack(alignment: .bottom, spacing: 8) {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                // Имя отправителя (только для партнёра)
                if !isMe {
                    Text(action.fromUserName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }

                // Пузырь
                VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                    Text(action.typeLabel)
                        .font(.subheadline)
                        .foregroundColor(isMe ? .white : .primary)

                    if !action.proposedValue.isEmpty {
                        Text(action.proposedValue)
                            .font(.caption)
                            .foregroundColor(isMe ? .white.opacity(0.85) : .secondary)
                    }

                    HStack(spacing: 4) {
                        Text(action.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(isMe ? .white.opacity(0.7) : Color(.systemGray3))

                        // Статус только для моих
                        if isMe {
                            statusIcon(action.status)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isMe ? Color.green : Color(.systemGray5))
                .cornerRadius(16)
                .cornerRadius(isMe ? 4 : 16, corners: isMe ? .topRight : .topLeft)

                // Кнопки ответа (только для pending от партнёра)
                if !isMe && action.status == .pending {
                    HStack(spacing: 8) {
                        Button {
                            respond(action: action, accept: true)
                        } label: {
                            Text("Принять")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(isProcessing)

                        Button {
                            respond(action: action, accept: false)
                        } label: {
                            Text("Отклонить")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray5))
                                .foregroundColor(.red)
                                .cornerRadius(12)
                        }
                        .disabled(isProcessing)
                    }
                }
            }

            if !isMe { Spacer(minLength: 60) }
        }
    }

    // MARK: - Кнопки действий

    private var actionButtons: some View {
        VStack(spacing: 0) {
            if myActionPending {
                // Ждём ответа партнёра
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text("Ожидаем ответа партнёра...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color(.systemGray6))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {

                        actionChip(
                            icon: "checkmark.circle.fill",
                            title: "Подтверждаю",
                            color: .green
                        ) { send(type: .confirm) }

                        actionChip(
                            icon: "clock.arrow.2.circlepath",
                            title: "Другое время",
                            color: .blue
                        ) { showTimePicker = true }

                        actionChip(
                            icon: "mappin.and.ellipse",
                            title: "Другое место",
                            color: .orange
                        ) { showLocationPicker = true }

                        actionChip(
                            icon: "xmark.circle",
                            title: "Отменить встречу",
                            color: .red
                        ) { send(type: .cancelRequest) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemBackground))
            }
        }
    }

    private func actionChip(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .disabled(isProcessing)
    }

    // MARK: - Пустое состояние

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundColor(.gray)
            Text(isDraft
                 ? "Партнёр увидит этот диалог после вашего первого сообщения"
                 : "Начните уточнение деталей встречи")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Sheets

    private var timePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Выберите удобный слот")
                    .font(.headline)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                let slots = [
                    "08:00 – 10:00", "10:00 – 12:00",
                    "12:00 – 14:00", "14:00 – 16:00",
                    "16:00 – 18:00", "18:00 – 20:00",
                    "20:00 – 22:00"
                ]

                ForEach(slots, id: \.self) { slot in
                    Button {
                        showTimePicker = false
                        send(type: .suggestTime, value: slot)
                    } label: {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.green)
                            Text(slot)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }
                    Divider().padding(.leading, 20)
                }
                Spacer()
            }
            .navigationTitle("Другое время")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showTimePicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var locationPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Предложите место")
                    .font(.headline)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                let options = [
                    ("Любой клуб в городе",     "building.2"),
                    ("Ближе к центру города",    "mappin.circle"),
                    ("Ближе ко мне",             "house"),
                    ("Ближе к вам",              "person.crop.circle")
                ]

                ForEach(options, id: \.0) { option, icon in
                    Button {
                        showLocationPicker = false
                        send(type: .suggestLocation, value: option)
                    } label: {
                        HStack {
                            Image(systemName: icon)
                                .foregroundColor(.green)
                                .frame(width: 24)
                            Text(option)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }
                    Divider().padding(.leading, 20)
                }
                Spacer()
            }
            .navigationTitle("Другое место")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showLocationPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM"
        return f.string(from: clarification.sparringDate)
    }

    private func statusIcon(_ status: MeetingActionStatus) -> some View {
        Group {
            switch status {
            case .pending:
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            case .accepted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.white)
            case .declined:
                Image(systemName: "xmark.circle")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private func loadActions() {
        // Для draft-диалога нечего загружать — экшенов ещё нет
        if isDraft && realClarificationId == nil {
            actions = []
            isLoading = false
            return
        }

        let idToLoad = realClarificationId ?? clarification.id
        isLoading = true
        service.loadActions(clarificationId: idToLoad) { loaded in
            self.actions = loaded
            self.isLoading = false
        }
    }
    private func send(type: MeetingActionType, value: String = "") {
        // Нельзя отправлять заблокированному
        if isBlocked {
            return
        }
        debugLog("🟡 send вызван, type: \(type.rawValue), isDraft: \(isDraft), realId: \(realClarificationId ?? "nil")")
        isProcessing = true

        // Если диалог ещё draft — создаём его вместе с первым действием
        if isDraft && realClarificationId == nil {
            service.createDraftWithFirstAction(
                draftClarification: clarification,
                actionType: type,
                proposedValue: value,
                fromUserId: currentUserId,
                fromUserName: currentUserName
            ) { realId in
                self.isProcessing = false
                if let id = realId {
                    self.realClarificationId = id
                    // Загружаем действия из нового диалога
                    self.loadActions()
                }
            }
            return
        }

        // Обычная отправка в существующий диалог
        let idToUse = realClarificationId ?? clarification.id
        service.sendAction(
            clarificationId: idToUse,
            fromUserId: currentUserId,
            fromUserName: currentUserName,
            type: type,
            proposedValue: value
        ) { success in
            isProcessing = false
            if success { loadActions() }
        }
    }

    private func respond(action: MeetingAction, accept: Bool) {
        isProcessing = true
        let idToUse = realClarificationId ?? clarification.id
        service.respondToAction(
            actionId: action.id,
            clarificationId: idToUse,
            sparringRequestId: clarification.sparringRequestId,
            accept: accept,
            action: action
        ) { success in
            isProcessing = false
            if success { loadActions() }
        }
    }
    // MARK: - Блокировка

    private func checkBlockStatus() {
        BlockService.shared.loadBlocks {
            self.isBlocked = BlockService.shared.isBlocked(self.partnerId)
        }
    }

    private func blockPartner() {
        isProcessing = true
        BlockService.shared.block(userId: partnerId) { success in
            isProcessing = false
            if success {
                isBlocked = true
                // Закрываем диалог — встреча отменена, контакта больше нет
                appState.clarificationToOpen = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    dismiss()
                }
            }
        }
    }

    private func unblockPartner() {
        isProcessing = true
        BlockService.shared.unblock(userId: partnerId) { success in
            isProcessing = false
            if success {
                isBlocked = false
            }
        }
    }
}

// MARK: - Скругление отдельных углов

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
