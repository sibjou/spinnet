import SwiftUI
import Combine

// MARK: - ClarificationDetailView
// Диалог по встрече. Как в мессенджерах: сверху аватар и «в сети / был(а) …», в переписке
// сообщения с галочками «отправлено / прочитано», внизу быстрые действия и поле ввода.
// Предложения (время, место, отмена) приходят карточкой с кнопками «Принять» и «Отклонить».
struct ClarificationDetailView: View {
    let clarification: MeetingClarification
    @ObservedObject var authService: AuthService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var service = ClarificationService()
    @StateObject private var presence = PartnerPresenceStore()

    // Свежая версия диалога (прочитанность, новое время и место); пока её нет — та, с которой открыли
    @State private var live: MeetingClarification? = nil
    // Первое сообщение отправлено — диалог из черновика стал настоящим
    @State private var created = false
    @State private var actions: [MeetingAction] = []
    @State private var actionsLoaded = false

    @State private var draftText = ""
    @State private var isSending = false
    @State private var isProcessing = false
    @State private var iBlockedPartner = false
    @State private var partnerBlockedMe = false
    @State private var now = Date()

    @State private var showProfile = false
    @State private var showTimeSheet = false
    @State private var showPlaceSheet = false
    @State private var showLateDialog = false
    @State private var showCancelConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showBlockConfirm = false
    @State private var errorMessage: String? = nil

    @FocusState private var composerFocused: Bool

    private let bottomAnchorId = "chat-bottom"
    private let clockTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // MARK: Состояние

    private var current: MeetingClarification { live ?? clarification }
    private var currentUserId: String { authService.currentUserId ?? "" }
    private var me: ChatActor {
        ChatActor(id: currentUserId, name: authService.userProfile?.fullName ?? "")
    }

    private var dialogId: String { clarification.sparringRequestId }
    private var partnerId: String { current.partnerId(currentUserId: currentUserId) }
    private var partnerName: String {
        let name = current.partnerName(currentUserId: currentUserId)
        return name.isEmpty ? "Партнёр" : name
    }
    private var partnerInfo: PresenceInfo { presence.info(for: partnerId) }

    /// Диалога в базе ещё нет: он появится вместе с первым сообщением
    private var isDraft: Bool { clarification.id.hasPrefix("draft_") && !created }
    private var isBlocked: Bool { iBlockedPartner || partnerBlockedMe }
    private var isClosed: Bool { current.status == "cancelled" || current.status == "deleted" }

    private var closedText: String {
        current.status == "cancelled" ? "Встреча отменена" : "Диалог удалён"
    }

    private var hasPendingFromPartner: Bool {
        actions.contains { $0.status == .pending && $0.fromUserId != currentUserId }
    }

    private var hasMyPending: Bool {
        actions.contains { $0.status == .pending && $0.fromUserId == currentUserId }
    }

    private var pendingHint: String? {
        if hasPendingFromPartner { return "Ответьте на предложение выше: примите или отклоните" }
        if hasMyPending { return "Ждём ответа партнёра" }
        return nil
    }

    private var canSend: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    // MARK: Экран

    var body: some View {
        VStack(spacing: 0) {
            MeetingSummaryCard(
                dateText: ChatTime.dayMonthFull(current.sparringDate),
                slot: current.sparringTimeSlot,
                city: current.sparringCity,
                location: current.sparringLocation,
                onOpenMap: openMeetingInMaps
            )
            Divider()
            messageList
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { titleView }
            ToolbarItem(placement: .navigationBarTrailing) { moreMenu }
        }
        .navigationDestination(isPresented: $showProfile) {
            PlayerProfileView(userId: partnerId)
        }
        .sheet(isPresented: $showTimeSheet) {
            ProposeTimeSheet(
                currentDay: current.sparringDate,
                currentSlot: current.sparringTimeSlot
            ) { day, slot, isNewDay in
                var action = OutgoingAction(type: .suggestTime, value: slot)
                if isNewDay { action.proposedDate = day }
                send(action)
            }
        }
        .sheet(isPresented: $showPlaceSheet) {
            ProposePlaceSheet(
                city: current.sparringCity,
                currentLatitude: current.sparringLatitude,
                currentLongitude: current.sparringLongitude
            ) { name, latitude, longitude, note in
                send(OutgoingAction(
                    type: .suggestLocation, value: name,
                    latitude: latitude, longitude: longitude, note: note
                ))
            }
        }
        .confirmationDialog("На сколько опаздываете?", isPresented: $showLateDialog, titleVisibility: .visible) {
            ForEach([5, 10, 15, 30], id: \.self) { minutes in
                Button("На \(minutes) мин") {
                    send(OutgoingAction(type: .late, value: "\(minutes)"))
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Предложить отменить встречу?", isPresented: $showCancelConfirm) {
            Button("Нет", role: .cancel) {}
            Button("Предложить", role: .destructive) {
                send(OutgoingAction(type: .cancelRequest))
            }
        } message: {
            Text("Встреча отменится, только если \(partnerName) согласится.")
        }
        .alert("Удалить диалог?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) { deleteDialog() }
        } message: {
            Text("Переписка будет удалена у обоих участников. Сама встреча останется.")
        }
        .alert("Заблокировать игрока?", isPresented: $showBlockConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Заблокировать", role: .destructive) { blockPartner() }
        } message: {
            Text("Вы больше не увидите друг друга. Эта встреча будет отменена.")
        }
        .alert("Не получилось", isPresented: errorBinding) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear { start() }
        .onDisappear { stop() }
        .onReceive(clockTimer) { now = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { markReadIfNeeded() }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding<Bool>(
            get: { errorMessage != nil },
            set: { shown in if !shown { errorMessage = nil } }
        )
    }

    // MARK: Шапка

    private var titleView: some View {
        Button {
            showProfile = true
        } label: {
            HStack(spacing: 8) {
                OnlineAvatar(
                    fullName: partnerName,
                    userId: partnerId,
                    size: 34,
                    isOnline: partnerInfo.showsOnlineDot(now: now)
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text(partnerName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    PresenceText(info: partnerInfo)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Профиль игрока \(partnerName)")
    }

    private var moreMenu: some View {
        Menu {
            Button {
                showProfile = true
            } label: {
                Label("Профиль игрока", systemImage: "person.crop.circle")
            }

            if iBlockedPartner {
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

            if !isDraft {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Удалить диалог", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: Переписка

    private struct ChatRow: Identifiable {
        let id: String
        let separator: String?
        let action: MeetingAction?
    }

    /// События по порядку, перед первым событием каждого дня — заголовок дня
    private var rows: [ChatRow] {
        var result: [ChatRow] = []
        var previous: Date? = nil
        for action in actions {
            if ChatTime.needsDaySeparator(previous: previous, current: action.createdAt) {
                result.append(ChatRow(
                    id: "day-\(action.id)",
                    separator: ChatTime.daySeparator(action.createdAt),
                    action: nil
                ))
            }
            result.append(ChatRow(id: action.id, separator: nil, action: action))
            previous = action.createdAt
        }
        return result
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if !actionsLoaded && !isDraft {
                        ProgressView().padding(.top, 40)
                    } else if actions.isEmpty {
                        emptyState
                    } else {
                        ForEach(rows) { row in
                            if let separator = row.separator {
                                DaySeparatorView(text: separator)
                            } else if let action = row.action {
                                bubble(for: action)
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id(bottomAnchorId)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .defaultScrollAnchor(actions.isEmpty ? UnitPoint.center : UnitPoint.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: actions.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                }
                if let last = actions.last, last.fromUserId != currentUserId {
                    markReadIfNeeded()
                }
            }
            .onChange(of: composerFocused) { _, focused in
                guard focused else { return }
                // Клавиатура поднимается не мгновенно
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation { proxy.scrollTo(bottomAnchorId, anchor: .bottom) }
                }
            }
        }
    }

    private func bubble(for action: MeetingAction) -> some View {
        let mine = action.fromUserId == currentUserId
        return ActionBubble(
            action: action,
            isMine: mine,
            isRead: mine && ReadReceipt.isRead(
                sentAt: action.createdAt,
                partnerReadAt: current.readAt[partnerId]
            ),
            city: current.sparringCity,
            canRespond: !mine && action.status == .pending && !isClosed && !isBlocked,
            isBusy: isProcessing,
            onAccept: { respond(to: action, accept: true) },
            onDecline: { respond(to: action, accept: false) }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundColor(.gray)
            Text(isDraft
                 ? "Партнёр увидит этот диалог после вашего первого сообщения"
                 : "Договоритесь о деталях: подтвердите встречу, предложите время или место, или просто напишите")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: Нижняя панель

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            if isClosed {
                banner(closedText, icon: "lock.fill")
            } else if isBlocked {
                banner(iBlockedPartner ? "Вы заблокировали этого игрока" : "Переписка недоступна",
                       icon: "hand.raised.fill")
            } else {
                if let hint = pendingHint {
                    Text(hint)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 6)
                }
                quickActions
                composer
            }
        }
        .background(.bar)
    }

    private func banner(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(16)
    }

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !(hasPendingFromPartner || hasMyPending) {
                    chip("Подтверждаю", icon: "checkmark.seal.fill", color: AppColor.primary) {
                        send(OutgoingAction(type: .confirm))
                    }
                    chip("Другое время", icon: "clock.arrow.2.circlepath", color: AppColor.primary) {
                        composerFocused = false
                        showTimeSheet = true
                    }
                    chip("Другое место", icon: "mappin.and.ellipse", color: AppColor.primary) {
                        composerFocused = false
                        showPlaceSheet = true
                    }
                }
                chip("Опаздываю", icon: "clock.badge.exclamationmark", color: AppColor.warning) {
                    composerFocused = false
                    showLateDialog = true
                }
                chip("Я на месте", icon: "figure.walk", color: AppColor.success) {
                    send(OutgoingAction(type: .arrived))
                }
                if !(hasPendingFromPartner || hasMyPending) {
                    chip("Отменить встречу", icon: "xmark.circle", color: AppColor.danger) {
                        showCancelConfirm = true
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
        }
        .disabled(isSending || isProcessing)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Сообщение", text: $draftText, axis: .vertical)
                .lineLimit(1...4)
                .focused($composerFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .onChange(of: draftText) { _, value in
                    if value.count > 500 { draftText = String(value.prefix(500)) }
                }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(canSend ? AppColor.primary : Color(.systemGray3))
            }
            .disabled(!canSend)
            .accessibilityLabel("Отправить")
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    // MARK: Жизненный цикл

    private func start() {
        presence.watch([partnerId])
        checkBlockStatus()
        if isDraft {
            actionsLoaded = true
        } else {
            startListening()
        }
    }

    private func stop() {
        service.stopMetaListener()
        service.stopActionsListener()
        presence.stop()
    }

    private func startListening() {
        service.listenClarification(id: dialogId) { updated in
            if let updated { live = updated }
        }
        service.loadActions(clarificationId: dialogId) { loaded in
            actions = loaded
            actionsLoaded = true
        }
        markReadIfNeeded()
    }

    /// Человек видит диалог — непрочитанных у него нет, а партнёр увидит «прочитано»
    private func markReadIfNeeded() {
        guard !isDraft, scenePhase == .active, !currentUserId.isEmpty else { return }
        service.markRead(clarificationId: dialogId, userId: currentUserId)
    }

    // MARK: Отправка и ответы

    private func send(_ action: OutgoingAction, completion: ((Bool) -> Void)? = nil) {
        guard !isBlocked, !isClosed, !isSending, !currentUserId.isEmpty else { return }
        isSending = true
        let wasDraft = isDraft

        service.send(action, in: current, isDraft: wasDraft, from: me) { id in
            isSending = false
            guard id != nil else {
                errorMessage = "Не удалось отправить. Проверьте интернет и попробуйте ещё раз."
                completion?(false)
                return
            }
            if wasDraft {
                // Документ диалога появился — теперь на него можно подписаться
                created = true
                startListening()
            }
            completion?(true)
        }
    }

    private func sendMessage() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard ContentModeration.isAcceptableMessage(text) else {
            errorMessage = "В сообщении есть недопустимые выражения. Перефразируйте."
            return
        }
        // Поле очищаем сразу, как в мессенджерах; при ошибке текст возвращаем
        draftText = ""
        send(OutgoingAction(type: .message, value: text)) { success in
            if !success && draftText.isEmpty { draftText = text }
        }
    }

    private func respond(to action: MeetingAction, accept: Bool) {
        guard !isProcessing else { return }
        isProcessing = true
        service.respondToAction(
            action: action,
            clarification: current,
            clarificationId: dialogId,
            responder: me,
            accept: accept
        ) { success in
            isProcessing = false
            if !success { errorMessage = "Не удалось ответить. Попробуйте ещё раз." }
        }
    }

    // MARK: Карта

    private func openMeetingInMaps() {
        MapsOpener.open(
            name: current.sparringLocation,
            city: current.sparringCity,
            latitude: current.sparringLatitude,
            longitude: current.sparringLongitude
        )
    }

    // MARK: Удаление и блокировка

    private func deleteDialog() {
        service.deleteClarification(id: dialogId)
        dismiss()
    }

    private func checkBlockStatus() {
        BlockService.shared.loadBlocks {
            iBlockedPartner = BlockService.shared.blockedUserIds.contains(partnerId)
            partnerBlockedMe = BlockService.shared.blockedByUserIds.contains(partnerId)
        }
    }

    private func blockPartner() {
        isProcessing = true
        BlockService.shared.block(userId: partnerId) { success in
            isProcessing = false
            if success {
                iBlockedPartner = true
                // Контакта больше нет — закрываем диалог
                dismiss()
            }
        }
    }

    private func unblockPartner() {
        isProcessing = true
        BlockService.shared.unblock(userId: partnerId) { success in
            isProcessing = false
            if success { iBlockedPartner = false }
        }
    }
}
