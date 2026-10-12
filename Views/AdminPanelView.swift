import SwiftUI

struct AdminPanelView: View {
    @State private var pendingReviews: [Review] = []
    @State private var isLoading = true
    @State private var actionInProgress: String? = nil
    @State private var revisionReviewId: String? = nil
    @State private var revisionReason = ""
    @State private var showRevisionDialog = false

    private let service = ReviewService()

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            if isLoading {
                ProgressView()
            } else if pendingReviews.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: AppSpacing.m) {
                        // Информационный блок
                        infoBanner

                        ForEach(pendingReviews) { review in
                            reviewCard(review)
                        }
                    }
                    .padding(AppSpacing.l)
                }
            }
        }
        .navigationTitle("Модерация")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear { load() }
        .alert("Запросить правку", isPresented: $showRevisionDialog) {
            TextField("Причина (например: нецензурная лексика)", text: $revisionReason)
            Button("Отмена", role: .cancel) {
                revisionReviewId = nil
                revisionReason = ""
            }
            Button("Отправить") {
                sendRevisionRequest()
            }
        } message: {
            Text("Автору придёт уведомление с просьбой отредактировать отзыв")
        }
    }

    // MARK: - Информация о модерации

    private var infoBanner: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(AppColor.info)
                Text("В очереди: \(pendingReviews.count)")
                    .font(.subheadline.bold())
            }
            Text("Выберите действие: одобрить — отзыв станет публичным; запросить правку — автор получит уведомление; удалить — отзыв исчезнет навсегда")
                .font(.caption)
                .foregroundColor(AppColor.textSecondary)
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.medium)
    }

    // MARK: - Карточка отзыва

    private func reviewCard(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {

            // Автор и звёзды
            HStack(spacing: AppSpacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.fromUserName)
                        .font(.subheadline.bold())
                    Text("Кому: \(review.toUserId.prefix(8))…")
                        .font(.caption2)
                        .foregroundColor(AppColor.textSecondary)
                }
                Spacer()
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= review.rating ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundColor(AppColor.star)
                    }
                }
            }

            // Дата
            Text(formattedDate(review.createdAt))
                .font(.caption)
                .foregroundColor(AppColor.textTertiary)

            // Текст отзыва
            if !review.comment.isEmpty {
                Text(review.comment)
                    .font(.subheadline)
                    .padding(AppSpacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColor.background)
                    .cornerRadius(AppRadius.small)
            } else {
                Text("(без комментария)")
                    .font(.caption.italic())
                    .foregroundColor(AppColor.textTertiary)
            }

            // Кнопки действий — два ряда
            VStack(spacing: AppSpacing.s) {
                // Ряд 1: Одобрить
                Button {
                    approve(review)
                } label: {
                    HStack(spacing: 4) {
                        if actionInProgress == review.id {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text("Одобрить и опубликовать")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.s)
                    .background(AppColor.primary)
                    .cornerRadius(AppRadius.small)
                }
                .disabled(actionInProgress != nil)

                // Ряд 2: Запросить правку + Удалить
                HStack(spacing: AppSpacing.s) {
                    Button {
                        revisionReviewId = review.id
                        revisionReason = ""
                        showRevisionDialog = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                            Text("Правка")
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.s)
                        .background(AppColor.warning)
                        .cornerRadius(AppRadius.small)
                    }
                    .disabled(actionInProgress != nil)

                    Button {
                        delete(review)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                            Text("Удалить")
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.s)
                        .background(AppColor.danger)
                        .cornerRadius(AppRadius.small)
                    }
                    .disabled(actionInProgress != nil)
                }
            }
        }
        .padding(AppSpacing.l)
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.large)
    }

    // MARK: - Пустое состояние
    private var emptyState: some View {
        VStack(spacing: AppSpacing.m) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(AppColor.primary)
            Text("Всё чисто!")
                .font(.title3.bold())
            Text("Нет отзывов на модерации")
                .font(.subheadline)
                .foregroundColor(AppColor.textSecondary)
        }
        .padding(AppSpacing.xxl)
    }

    // MARK: - Действия

    private func load() {
        isLoading = true
        service.loadPendingReviews { reviews in
            pendingReviews = reviews
            isLoading = false
        }
    }

    private func approve(_ review: Review) {
        actionInProgress = review.id
        service.approveReview(reviewId: review.id) { success in
            actionInProgress = nil
            if success {
                pendingReviews.removeAll { $0.id == review.id }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func delete(_ review: Review) {
        actionInProgress = review.id
        service.deleteReview(reviewId: review.id) { success in
            actionInProgress = nil
            if success {
                pendingReviews.removeAll { $0.id == review.id }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func sendRevisionRequest() {
        guard let id = revisionReviewId,
              let review = pendingReviews.first(where: { $0.id == id }),
              !revisionReason.isEmpty else { return }

        actionInProgress = id
        service.requestRevision(
            reviewId: id,
            fromUserName: review.fromUserName,
            reason: revisionReason
        ) { success in
            actionInProgress = nil
            revisionReviewId = nil
            revisionReason = ""
            if success {
                pendingReviews.removeAll { $0.id == id }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f.string(from: date)
    }
}
