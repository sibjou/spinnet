import SwiftUI

struct ContentView: View {
    @StateObject private var authService = AuthService()
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
        // При запуске и возвращении в приложение — проверяем валидность аккаунта
        .onAppear {
            authService.verifyCurrentUser()
            // Проверяю статусы при каждом запуске
            StatusManager.shared.checkAllStatuses()
        }
    }
}
