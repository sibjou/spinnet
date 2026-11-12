import SwiftUI

// MARK: - ProfileView: шапка
// Шапку рисует общий компонент ProfileHeaderView — он же используется на странице другого игрока.

extension ProfileView {

    var profileHeader: some View {
        ProfileHeaderView(
            userId: authService.currentUserId ?? "",
            firstName: userData["firstName"] as? String ?? "",
            lastName: userData["lastName"] as? String ?? "",
            city: userData["city"] as? String ?? "",
            skillLevel: userData["skillLevel"] as? String ?? "",
            grip: userData["grip"] as? String ?? "",
            playStyle: userData["playStyle"] as? String ?? "",
            gamesCount: sparringService.completedGamesCount,
            tournamentsCount: tournamentsCount,
            ttwRating: userData["ttwRating"] as? Int ?? 0,
            averageRating: averageRating,
            reviewsCount: reviewsCount,
            onTapReviews: { showReviewsList = true }
        )
    }
}
