import SwiftUI

struct ContentView: View {
    // Единый экземпляр создаётся в SpinnetApp и приходит через окружение
    @EnvironmentObject private var authService: AuthService
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
            if !newValue {
                showRegister = false
            }
        }
        // При запуске и возвращении в приложение — проверяем аккаунт и статусы игр
        .onAppear { refreshOnForeground() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshOnForeground() }
        }
    }

    private func refreshOnForeground() {
        guard authService.isLoggedIn else { return }
        authService.verifyCurrentUser()
        StatusManager.shared.checkAllStatuses()
    }
}
