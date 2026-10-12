import SwiftUI
import FirebaseFirestore

struct ReviewsListView: View {
    let userId: String
    let userName: String

    @State private var reviews: [Review] = []
    @State private var isLoading = true
    @State private var averageRating: Double = 0

    // Актуальные имена авторов отзывов (подгружаются живьём из users)
    @State private var liveNames: [String: String] = [:]

    private let service = ReviewService()

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.l) {

                if !reviews.isEmpty {
                    ratingSummary
                }

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if reviews.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: AppSpacing.m) {
                        ForEach(reviews) { review in
                            reviewCard(review)
                        }
                    }
                }
            }
            .padding(AppSpacing.l)
        }
        .background(AppColor.background)
        .navigationTitle("Отзывы")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
    }

    private var ratingSummary: some View {
        VStack(spacing: AppSpacing.s) {
            Text(String(format: "%.1f", averageRating))
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(AppColor.textPrimary)

            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= Int(averageRating.rounded()) ? "star.fill" : "star")
                        .font(.system(size: 16))
                        .foregroundColor(AppColor.star)
                }
            }

            Text("На основе \(reviews.count) \(reviewCountText(reviews.count))")
                .font(.subheadline)
                .foregroundColor(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.l)
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.large)
    }

    private func reviewCard(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack {
                HStack(spacing: AppSpacing.s) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(AppColor.primary)
                    // Показываем актуальное имя если подгрузили, иначе денормализованное
                    Text(liveNames[review.fromUserId] ?? review.fromUserName)
                        .font(.subheadline.bold())
                        .foregroundColor(AppColor.textPrimary)
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

            if !review.comment.isEmpty {
                Text(review.comment)
                    .font(.subheadline)
                    .foregroundColor(AppColor.textPrimary)
                    .padding(.top, AppSpacing.xs)
            }

            Text(formattedDate(review.createdAt))
                .font(.caption)
                .foregroundColor(AppColor.textTertiary)
        }
        .padding(AppSpacing.l)
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.large)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.m) {
            Image(systemName: "star.slash")
                .font(.system(size: 44))
                .foregroundColor(AppColor.textTertiary)
            Text("Пока нет отзывов")
                .font(.headline)
                .foregroundColor(AppColor.textSecondary)
            Text("Сыграйте с \(userName) и оставьте первую оценку")
                .font(.subheadline)
                .foregroundColor(AppColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, AppSpacing.xxl)
    }

    private func load() {
        service.loadReviews(forUserId: userId) { loaded in
            reviews = loaded
            if !loaded.isEmpty {
                let sum = loaded.reduce(0) { $0 + $1.rating }
                averageRating = Double(sum) / Double(loaded.count)
            }
            isLoading = false

            // Подгружаем актуальные имена авторов отзывов
            loadLiveNames(for: loaded)
        }
    }

    // MARK: - Подгрузка актуальных имён авторов
    // Денормализованное имя в отзыве может устареть, поэтому берём живьём из users
    private func loadLiveNames(for reviews: [Review]) {
        let db = Firestore.firestore()
        let uniqueIds = Set(reviews.map { $0.fromUserId })

        for id in uniqueIds {
            db.collection("users").document(id).getDocument { doc, _ in
                guard let data = doc?.data() else { return }
                let firstName = data["firstName"] as? String ?? ""
                let lastName  = data["lastName"]  as? String ?? ""
                let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    DispatchQueue.main.async {
                        self.liveNames[id] = name
                    }
                }
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }

    private func reviewCountText(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 14 { return "отзывов" }
        switch mod10 {
        case 1: return "отзыва"
        case 2, 3, 4: return "отзывов"
        default: return "отзывов"
        }
    }
}
