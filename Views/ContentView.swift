import SwiftUI

struct ContentView: View {
    @StateObject private var authService = AuthService()
    @State private var showRegister = false
    
    var body: some View {
        // Следим за изменением isLoggedIn
        Group {
            if authService.isLoggedIn {
                MainTabView(authService: authService)
            } else if showRegister {
                RegisterView(showRegister: $showRegister, authService: authService)
            } else {
                LoginView(showRegister: $showRegister, authService: authService)
            }
        }
        // Когда пользователь выходит — сбрасываем на экран входа
        .onChange(of: authService.isLoggedIn) { _, newValue in
            if !newValue {
                showRegister = false
            }
        }
    }
}
