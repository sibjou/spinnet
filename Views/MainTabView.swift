import SwiftUI

struct MainTabView: View {
    @ObservedObject var authService: AuthService
    @EnvironmentObject var appState: AppState

    @State private var isTabBarVisible      = true
    @State private var showCreateSheet      = false
    @State private var showCreateRequest    = false
    @State private var showCreateTournament = false
    @ObservedObject private var notificationService = NotificationService.shared
    @StateObject private var clarificationService = ClarificationService()

    

    @StateObject private var tournamentService = TournamentService()

    var body: some View {
        ZStack(alignment: .bottom) {
            
            // Контент с отступом снизу под TabBar
            Group {
                switch appState.selectedTab {
                case .feed:
                    FeedView(authService: authService)
                case .tournaments:
                    TournamentListView(authService: authService)
                case .chat:
                    ChatListView(authService: authService, isTabBarVisible: $isTabBarVisible)
                case .profile:
                    ProfileView(authService: authService)
                }
            }
            .padding(.bottom, isTabBarVisible ? 49 : 0)
            
            // TabBar поверх
            customTabBar
        }
        .sheet(isPresented: $showCreateRequest) {
            CreateRequestView(authService: authService)
        }
        .sheet(isPresented: $showCreateTournament) {
            CreateTournamentView(
                authService: authService,
                tournamentService: tournamentService,
                isPresented: $showCreateTournament
            )
        }
        .confirmationDialog("Что создаём?", isPresented: $showCreateSheet, titleVisibility: .visible) {
            Button("🏓  Заявку на спарринг") { showCreateRequest    = true }
            Button("🏆  Турнир")             { showCreateTournament = true }
            Button("Отмена", role: .cancel)  {}
        }
        .onAppear {
            if let userId = authService.currentUserId {
                notificationService.startUnreadListener(userId: userId)
                clarificationService.startUnreadListener(currentUserId: userId)
            }
        }
        .onDisappear {
            clarificationService.stopUnreadListener()
        }
    }

    private var customTabBar: some View {
        VStack(spacing: 0) {
            Divider()
            ZStack {
                HStack(spacing: 0) {
                    tabBarButton(icon: "list.bullet",  title: "Лента",     tab: .feed)
                    tabBarButton(icon: "trophy",        title: "Турниры",   tab: .tournaments)
                    Spacer().frame(maxWidth: .infinity)
                    tabBarButton(
                        icon: "checklist",
                        title: "Уточнения",
                        tab: .chat,
                        badgeCount: clarificationService.unreadClarificationsCount
                    )
                    tabBarButton(
                        icon: "person.circle",
                        title: "Профиль",
                        tab: .profile,
                        badgeCount: notificationService.unreadCountValue
                    )
                }

                Button { showCreateSheet = true } label: {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 50, height: 50) // Размер круга
                            .shadow(color: .green.opacity(0.4), radius: 8, y: 4)
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold)) // Размер Плюса
                            .foregroundColor(.white)
                    }
                }
                .offset(y: -8) // НАСКОЛЬКО ПЛЮС ВЫСТУПАЕТ ВВЕРХ
            }
            .frame(height: 49)
            .background(Color(.systemBackground))
            //  УДАЛИЛИЛ: Color(.systemBackground).frame(height: 34)
        }
        .offset(y: isTabBarVisible ? 0 : 200)
        .animation(.easeInOut(duration: 0.25), value: isTabBarVisible)
    }

    private func tabBarButton(icon: String, title: String, tab: AppTab, badgeCount: Int = 0) -> some View {
        Button { appState.selectedTab = tab } label: {
            VStack(spacing: 3) {
                // Иконка с возможным красным бейджем с числом
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 19))

                    if badgeCount > 0 {
                        Text(badgeCount > 9 ? "9+" : "\(badgeCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 10, y: -6)
                    }
                }

                Text(title)
                    .font(.system(size: 9))
            }
            .foregroundColor(appState.selectedTab == tab ? .green : Color(.systemGray2))
            .frame(maxWidth: .infinity)
        }
    }
}

