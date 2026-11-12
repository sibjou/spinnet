import SwiftUI

struct ContentView: View {
    // Единый экземпляр создаётся в SpinnetApp и приходит через окружение
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var showRegister = false

    var body: some View {
        Group {
            if authService.isLoggedIn {
                MainTabView(authService: authService)
            } else if showRegister {
                RegisterView(showRegister: $showRegister, authService: authService)
            } else {
                LoginView(showRegister: $showRegister, authService: authService)
            }
        }
        .onChange(of: authService.isLoggedIn) { _, newValue in
            if newValue {
                markOnline()
            } else {
                showRegister = false
            }
        }
        // При запуске и возвращении в приложение — проверяем аккаунт и статусы игр.
        // На запуске проверка ждёт, пока появится лента: первому экрану она не нужна
        .onAppear {
            Perf.mark("экран: ContentView появился")
            refreshOnForeground()
        }
        .onChange(of: appState.isStartupDone) { _, done in
            if done { refreshOnForeground() }
        }
        .onChange(of: scenePhase) { _, phase in
            Perf.event("сцена: \(phase)")
            switch phase {
            case .active:
                refreshOnForeground()
            case .background:
                // Другие игроки увидят «был(а) в сети» с этого момента
                PresenceService.shared.goOffline()
            default:
                break
            }
        }
    }

    private func refreshOnForeground() {
        guard authService.isLoggedIn, appState.isStartupDone else { return }
        authService.verifyCurrentUser()
        StatusManager.shared.checkAllStatuses()
        markOnline()
    }

    /// Отметка «в сети» — только пока приложение на экране
    private func markOnline() {
        guard scenePhase == .active,
              let userId = authService.currentUserId, !userId.isEmpty else { return }
        PresenceService.shared.goOnline(userId: userId)
    }
}
