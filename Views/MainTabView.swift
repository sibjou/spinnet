import SwiftUI

// MARK: - MainTabView
// Главный экран с нижней навигацией
// TabView — стандартный компонент iOS для нижних вкладок
struct MainTabView: View {
    @ObservedObject var authService: AuthService
    
    var body: some View {
        TabView {
            FeedView(authService: authService)
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Лента")
                }
            
            TournamentListView(authService: authService)
                .tabItem {
                    Image(systemName: "trophy")
                    Text("Турниры")
                }
            
            CreateRequestView(authService: authService)
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                    Text("Создать")
                }
            
            ProfileView(authService: authService)
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("Профиль")
                }
        }
        .tint(.green)
    }
}
