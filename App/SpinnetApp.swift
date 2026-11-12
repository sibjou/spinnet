import SwiftUI
import FirebaseCore
import FirebaseFirestore

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    // Мост к AppState — устанавливается из SpinnetApp при запуске
    static weak var appState: AppState?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        Perf.start()
        // Зависание бывает не только на запуске, поэтому следим за экраном весь сеанс (до часа)
        Perf.watchMainThread(for: 3600)
        MainThreadProbe.shared.start(for: 3600)
        Perf.mark("запуск: \(BuildInfo.summary)")
        Perf.mark("запуск: \(DeviceCondition.summary)")
        Perf.mark("запуск: \(Self.launchConditions(application))")
        FirebaseApp.configure()

        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings

        UNUserNotificationCenter.current().delegate = self
        NotificationService.shared.requestPermission()
        Perf.mark("запуск: Firebase настроен")

        return true
    }

    /// Как приложение запущено: из Xcode ли, не заблокирован ли телефон, активно ли приложение.
    /// Заблокированный телефон и отладчик сильно замедляют запуск, а в замерах это не видно без отметки.
    private static func launchConditions(_ application: UIApplication) -> String {
        let state: String
        switch application.applicationState {
        case .active:     state = "активно"
        case .inactive:   state = "неактивно"
        case .background: state = "в фоне"
        @unknown default: state = "неизвестно"
        }
        let locked = application.isProtectedDataAvailable ? "нет" : "да"
        let debugger = isDebuggerAttached ? "подключён (запуск из Xcode)" : "нет"
        return "состояние приложения: \(state), телефон заблокирован: \(locked), отладчик: \(debugger)"
    }

    /// Подключён ли отладчик (флаг «процесс отлаживается» в системе)
    private static var isDebuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let status = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        return status == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
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
                // Календари и даты по языку приложения, а не по региону телефона
                .environment(\.locale, AppLocale.current)
                .onAppear {
                    // Связываем AppState с AppDelegate для обработки тапов по уведомлениям
                    AppDelegate.appState = appState
                }
        }
    }
}
