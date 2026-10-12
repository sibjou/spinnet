import SwiftUI

struct ChatListView: View {
    @ObservedObject var authService: AuthService
    @Binding var isTabBarVisible: Bool

    var body: some View {
        ClarificationListView(authService: authService, isTabBarVisible: $isTabBarVisible)
    }
}
