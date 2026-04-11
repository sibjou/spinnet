import SwiftUI
import FirebaseFirestore

struct ProfileView: View {
    @ObservedObject var authService: AuthService
    @State private var userData: [String: Any] = [:]
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView()
                } else {
                    HStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text("\(userData["firstName"] as? String ?? "") \(userData["lastName"] as? String ?? "")")
                                .font(.title2.bold())
                            Text("\(userData["skillLevel"] as? String ?? "") • \(userData["city"] as? String ?? "")")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    
                    Section("Игровые параметры") {
                        Label("Хват: \(userData["grip"] as? String ?? "—")", systemImage: "hand.raised")
                        Label("Стиль: \(userData["playStyle"] as? String ?? "—")", systemImage: "figure.table.tennis")
                    }
                    
                    Section {
                        Button("Выйти из аккаунта", role: .destructive) {
                            authService.logout()
                        }
                    }
                }
            }
            .navigationTitle("Профиль")
            .onAppear { loadProfile() }
        }
    }
    
    private func loadProfile() {
        guard let userId = authService.currentUserId else { return }
        Firestore.firestore().collection("users").document(userId).getDocument { doc, _ in
            DispatchQueue.main.async {
                isLoading = false
                userData = doc?.data() ?? [:]
            }
        }
    }
}
