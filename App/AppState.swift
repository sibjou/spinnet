import Foundation
import Combine

enum AppTab: CaseIterable {
    case feed, tournaments, chat, profile
}

class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .feed

    /// Заставка при запуске снята, лента на экране. Пока она не снята, второстепенная работа
    /// (проверка статусов, «в сети», счётчики непрочитанного) ждёт и не мешает показать первый экран
    @Published var isStartupDone = false
    @Published var clarificationToOpen: MeetingClarification? = nil
    @Published var pendingNotificationTarget: NotificationTarget? = nil

    /// Растёт, когда нужно закрыть все открытые окна (например, переход в «Мой профиль»).
    /// Экраны с окнами подписываются на изменение и закрывают свои.
    @Published var dismissSignal = 0

    // Обработка тапа по уведомлению.
    // - уточнение: открываем вкладку «Встречи» и нужный диалог;
    // - остальное: открываем профиль и запоминаем цель — профиль сам откроет игру,
    //   экран счёта или профиль человека (см. ProfileView.openPendingNotificationTarget).
    func handleNotificationTap(type: String, targetId: String?) {
        let target = NotificationTarget(type: type, targetId: targetId)

        if target.opensClarification, let id = targetId, !id.isEmpty {
            ClarificationService().fetchClarification(id: id) { [weak self] clarification in
                guard let self else { return }
                // Диалог мог быть закрыт или удалён — тогда просто открываем вкладку со списком
                self.selectedTab = .chat
                if let clarification {
                    self.clarificationToOpen = clarification
                }
            }
            return
        }

        selectedTab = .profile
        pendingNotificationTarget = target
    }

    /// Переход на свою страницу из любого места: закрывает окна и открывает вкладку «Профиль»
    func openOwnProfile() {
        dismissSignal += 1
        selectedTab = .profile
    }
}

// Цель перехода по уведомлению
struct NotificationTarget: Equatable {
    let type: String       // rawValue из NotificationType, например "match_proposed"
    let targetId: String?  // id игры, человека или диалога

    private var notificationType: NotificationType? { NotificationType(rawValue: type) }

    /// Уведомление ведёт на экран игры
    var opensGame: Bool { notificationType?.opensGame ?? false }

    /// Уведомление ведёт сразу на экран счёта матча
    var opensMatch: Bool { notificationType?.opensMatch ?? false }

    /// Уведомление ведёт сразу на форму отзыва
    var opensReview: Bool { notificationType?.opensReview ?? false }

    /// Уведомление ведёт в профиль человека
    var opensProfile: Bool { notificationType?.opensProfile ?? false }

    /// Уведомление ведёт в диалог уточнения
    var opensClarification: Bool { notificationType?.opensClarification ?? false }
}
