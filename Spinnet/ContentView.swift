import SwiftUI

struct ContentView: View {
    @StateObject private var authService = AuthService()
    @State private var showRegister = false
    
    var body: some View {
        if authService.isLoggedIn {
            MainTabView(authService: authService)
        } else if showRegister {
            RegisterView(showRegister: $showRegister, authService: authService)
        } else {
            LoginView(showRegister: $showRegister, authService: authService)
        }
    }
}
