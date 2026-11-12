import SwiftUI

/// После брони человек видит, что получилось, и в одно касание переходит в чат с партнёром:
/// договориться о времени и месте — следующий шаг, ради которого всё и делалось.
struct BookingSuccessView: View {
    let request: SparringRequest
    @ObservedObject var authService: AuthService

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var isOpeningChat = false
    @State private var messageAlert: String? = nil

    private var partnerName: String {
        request.authorFirstName.isEmpty ? "Игрок" : request.authorFirstName
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                header

                summary

                VStack(spacing: AppSpacing.s) {
                    Button(action: openChat) {
                        HStack(spacing: AppSpacing.s) {
                            if isOpeningChat { ProgressView().tint(.white) }
                            Text(chatButtonTitle)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isOpeningChat)

                    Text("Подтвердите время и место — так игра точно состоится.")
                        .font(.footnote)
                        .foregroundColor(AppColor.textSecondary)
                        .multilineTextAlignment(.center)

                    Button("Готово") { dismiss() }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppColor.primary)
                        .padding(.top, AppSpacing.xs)
                        .frame(minHeight: 44)
                }
            }
            .padding(AppSpacing.xl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(AppColor.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .alert("Чат", isPresented: Binding(
            get: { messageAlert != nil },
            set: { if !$0 { messageAlert = nil } }
        )) {
            Button("OK") { messageAlert = nil }
        } message: {
            Text(messageAlert ?? "")
        }
    }

    private var chatButtonTitle: String {
        request.authorFirstName.isEmpty ? "Написать" : "Написать \(request.authorFirstName)"
    }

    // MARK: Заголовок

    private var header: some View {
        VStack(spacing: AppSpacing.m) {
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 72, height: 72)
                .background(AppColor.success)
                .clipShape(Circle())
                .accessibilityHidden(true)

            Text("Вы записаны на игру")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text("\(request.authorFullName.isEmpty ? "Автор заявки" : request.authorFullName) получил уведомление")
                .font(.subheadline)
                .foregroundColor(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, AppSpacing.s)
    }

    // MARK: Когда и где

    private var summary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            row(icon: "calendar", text: AppDate.fullWithWeekday(request.date))
            row(icon: "clock", text: request.timeSlot)
            row(icon: "mappin.and.ellipse",
                text: [request.city, request.location].filter { !$0.isEmpty }.joined(separator: " · "))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.l)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        .accessibilityElement(children: .combine)
    }

    private func row(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.m) {
            Image(systemName: icon)
                .foregroundColor(AppColor.primary)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundColor(AppColor.textPrimary)
        }
    }

    // MARK: Чат

    /// Открывает диалог по заявке: существующий или новый черновик. Уважает настройку «Уточнения по встречам» у партнёра.
    private func openChat() {
        guard !isOpeningChat, let myId = authService.currentUserId else { return }
        guard ConnectionMonitor.shared.isOnline else {
            messageAlert = ConnectionRule.actionRejected
            return
        }
        isOpeningChat = true
        let myName = authService.userProfile?.fullName ?? ""

        UserService.shared.fetchUser(id: request.userId) { data in
            // Нет данных — аккаунт не прочитался, а не «запретил»: запрет бывает только явным
            let allowed = PrivacySettings(userData: data ?? [:]).allowClarifications
            guard allowed else {
                isOpeningChat = false
                messageAlert = "\(partnerName) отключил сообщения по встречам. Игра сохранена в профиле, во вкладке «Игры»."
                return
            }

            ClarificationService().findActiveClarification(forRequestId: request.id) { existing in
                isOpeningChat = false
                let chat = existing ?? MeetingClarification.draft(for: request, bookedById: myId, bookedByName: myName)
                guard let chat else {
                    messageAlert = "Не удалось открыть чат. Откройте игру в профиле, во вкладке «Игры»."
                    return
                }
                appState.clarificationToOpen = chat
                appState.selectedTab = .chat
                dismiss()
            }
        }
    }
}
