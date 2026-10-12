import SwiftUI

struct ReviewFormView: View {
    let toUserId: String
    let toUserName: String
    let sparringRequestId: String

    @ObservedObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var rating: Int = 0
    @State private var comment = ""
    @State private var isSubmitting = false
    @State private var error: String? = nil

    private let service = ReviewService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.l) {

                    // Партнёр
                    VStack(spacing: AppSpacing.s) {
                        InitialsAvatar(fullName: toUserName, userId: toUserId, size: 60)
                        Text("Как прошла игра\nс \(toUserName)?")
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, AppSpacing.xl)

                    // Звёзды
                    HStack(spacing: AppSpacing.s) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.system(size: 40))
                                .foregroundColor(star <= rating ? AppColor.star : AppColor.textTertiary)
                                .onTapGesture {
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                    rating = star
                                }
                        }
                    }
                    .padding(.vertical, AppSpacing.m)

                    // Описание оценки
                    if rating > 0 {
                        Text(ratingLabel)
                            .font(.subheadline)
                            .foregroundColor(AppColor.textSecondary)
                    }

                    // Комментарий (опционально)
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        Text("Комментарий (необязательно)")
                            .font(.subheadline)
                            .foregroundColor(AppColor.textSecondary)

                        TextEditor(text: $comment)
                            .frame(height: 100)
                            .padding(AppSpacing.s)
                            .background(AppColor.cardBackground)
                            .cornerRadius(AppRadius.medium)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.medium)
                                    .stroke(AppColor.separator, lineWidth: 1)
                            )
                            .onChange(of: comment) { _, newValue in
                                if newValue.count > 300 {
                                    comment = String(newValue.prefix(300))
                                }
                            }

                        Text("\(comment.count)/300")
                            .font(.caption)
                            .foregroundColor(AppColor.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if let error = error {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(AppColor.danger)
                    }

                    Spacer()
                }
                .padding(AppSpacing.l)
            }
            .navigationTitle("Оценка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        submit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Отправить")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(rating == 0 || isSubmitting)
                }
            }
        }
    }

    private var ratingLabel: String {
        switch rating {
        case 1: return "Плохо"
        case 2: return "Так себе"
        case 3: return "Нормально"
        case 4: return "Хорошо"
        case 5: return "Отлично"
        default: return ""
        }
    }

    private func submit() {
        guard let userId = authService.currentUserId,
              let profile = authService.userProfile else { return }

        isSubmitting = true
        error = nil

        let userName = "\(profile.firstName) \(profile.lastName)"
            .trimmingCharacters(in: .whitespaces)

        service.submitReview(
            fromUserId: userId,
            fromUserName: userName.isEmpty ? "Игрок" : userName,
            toUserId: toUserId,
            sparringRequestId: sparringRequestId,
            rating: rating,
            comment: comment.trimmingCharacters(in: .whitespacesAndNewlines)
        ) { success, message in
            isSubmitting = false
            if success {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                if let msg = message {
                    // Ушёл на модерацию — показываем сообщение и закрываем через 2 сек
                    error = msg
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        dismiss()
                    }
                } else {
                    dismiss()
                }
            } else {
                error = message ?? "Не удалось отправить отзыв"
            }
        }
    }
}
