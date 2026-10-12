import SwiftUI
import FirebaseFirestore

// MARK: - BlockedUsersView
// Список заблокированных пользователей с возможностью разблокировки
struct BlockedUsersView: View {
    @State private var blockedUsers: [(id: String, name: String)] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Загрузка...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if blockedUsers.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(blockedUsers, id: \.id) { user in
                        HStack {
                            InitialsAvatar(fullName: user.name, userId: user.id, size: AppSize.avatarSmall)
                            Text(user.name)
                                .fontWeight(.medium)
                            Spacer()
                            Button("Разблокировать") {
                                unblock(user.id)
                            }
                            .font(.subheadline)
                            .foregroundColor(.green)
                            .buttonStyle(.borderless)   // ← ограничивает зону нажатия только кнопкой
                        }
                        .padding(.vertical, 4)
                    }                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Заблокированные")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadBlockedUsers() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("Нет заблокированных")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Заблокированные игроки появятся здесь")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Загрузка списка с именами

    private func loadBlockedUsers() {
        isLoading = true
        BlockService.shared.loadBlocks {
            let ids = Array(BlockService.shared.blockedUserIds)

            guard !ids.isEmpty else {
                self.blockedUsers = []
                self.isLoading = false
                return
            }

            // Подгружаем имена заблокированных
            UserService.shared.fetchNames(ids: ids) { names in
                let result = ids.map { id -> (id: String, name: String) in
                    let name = names[id] ?? ""
                    return (id: id, name: name.isEmpty ? "Игрок" : name)
                }
                self.blockedUsers = result.sorted { $0.name < $1.name }
                self.isLoading = false
            }
        }
    }

    // MARK: - Разблокировка

    private func unblock(_ userId: String) {
        BlockService.shared.unblock(userId: userId) { success in
            if success {
                blockedUsers.removeAll { $0.id == userId }
            }
        }
    }
}
