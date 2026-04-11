import SwiftUI

struct MainTabView: View {
    @ObservedObject var authService: AuthService
    
    var body: some View {
        TabView {
            FeedView(authService: authService)
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Лента")
                }
            
            Text("Турниры — скоро")
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
