import Foundation
import Combine

enum AppTab {
    case feed, tournaments, chat, profile
}

class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .feed
    @Published var clarificationToOpen: MeetingClarification? = nil
    @Published var pendingNotificationTarget: NotificationTarget? = nil

    // Обработка тапа по уведомлению — переключает вкладку и сохраняет цель
    func handleNotificationTap(type: String, targetId: String?) {
        switch type {
        case "game_reminder", "cancellation", "requestBooked":
            // Игровые уведомления → вкладка профиля (там предстоящие игры)
            selectedTab = .profile
        case "review_reminder":
            // Оценка игрока → профиль (там завершённые игры)
            selectedTab = .profile
        case "revision_request":
            // Правка отзыва → профиль
            selectedTab = .profile
        default:
            selectedTab = .profile
        }

        pendingNotificationTarget = NotificationTarget(type: type, targetId: targetId)
    }
}

// Цель перехода по уведомлению
struct NotificationTarget: Equatable {
    let type: String       // game_reminder, review_reminder, cancellation, requestBooked, revision_request
    let targetId: String?  // id игры/события
}
