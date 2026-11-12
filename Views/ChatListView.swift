import SwiftUI

struct ChatListView: View {
    @ObservedObject var authService: AuthService

    var body: some View {
        ClarificationListView(authService: authService)
    }
}
