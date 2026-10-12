import SwiftUI
import FirebaseCore
import FirebaseFirestore

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    // Мост к AppState — устанавливается из SpinnetApp при запуске
    static weak var appState: AppState?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()

        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings

        UNUserNotificationCenter.current().delegate = self
        NotificationService.shared.requestPermission()

        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    // Тап по уведомлению
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        let type = userInfo["type"] as? String ?? ""
        // requestId есть у локальных напоминаний, targetId — у Firestore-уведомлений
        let targetId = (userInfo["requestId"] as? String) ?? (userInfo["targetId"] as? String)

        DispatchQueue.main.async {
            AppDelegate.appState?.handleNotificationTap(type: type, targetId: targetId)
        }

        completionHandler()
    }
}

@main
struct SpinnetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthService()
    @StateObject private var appState    = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(appState)
                .onAppear {
                    // Связываем AppState с AppDelegate для обработки тапов по уведомлениям
                    AppDelegate.appState = appState
                }
        }
    }
}
