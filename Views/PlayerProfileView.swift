import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - PlayerProfileView
// Экран просмотра профиля другого игрока
// Открывается при нажатии на имя в ленте или в турнире
struct PlayerProfileView: View {
    let userId: String

    @State private var userData: [String: Any] = [:]
    @State private var isLoading = true
    @State private var gamesCount = 0

    // Блокировка
    @State private var isBlockedByMe = false      // я заблокировал его
    @State private var isBlockedByThem = false    // он заблокировал меня
    @State private var showBlockConfirm = false
    @State private var isProcessingBlock = false

    private var currentUserId: String { Auth.auth().currentUser?.uid ?? "" }
    private var isMyProfile: Bool { userId == currentUserId }

    // Профиль недоступен если кто-то кого-то заблокировал
    private var isUnavailable: Bool { isBlockedByMe || isBlockedByThem }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding(.top, 50)
            } else if isUnavailable {
                unavailableState
            } else {
                profileContent
            }
        }
        .navigationTitle("Профиль игрока")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Кнопка блокировки — только для чужого профиля и если он не заблокировал меня
            if !isMyProfile && !isBlockedByThem {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if isBlockedByMe {
                            Button {
                                unblockUser()
                            } label: {
                                Label("Разблокировать", systemImage: "person.crop.circle.badge.checkmark")
                            }
                        } else {
                            Button(role: .destructive) {
                                showBlockConfirm = true
                            } label: {
                                Label("Заблокировать", systemImage: "person.crop.circle.badge.xmark")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Заблокировать игрока?", isPresented: $showBlockConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Заблокировать", role: .destructive) { blockUser() }
        } message: {
            Text("Вы больше не увидите друг друга в ленте. Все забронированные игры между вами будут отменены.")
        }
        .onAppear { loadPlayerData() }
    }

    // MARK: - Контент профиля

    private var profileContent: some View {
        VStack(spacing: 20) {
            // Аватарка и имя
            VStack(spacing: 8) {
                InitialsAvatar(
                    firstName: userData["firstName"] as? String ?? "",
                    lastName:  userData["lastName"]  as? String ?? "",
                    userId:    userId,
                    size: AppSize.avatarLarge
                )

                Text("\(userData["firstName"] as? String ?? "") \(userData["lastName"] as? String ?? "")")
                    .font(.title2.bold())

                Text("\(userData["skillLevel"] as? String ?? "") • \(userData["city"] as? String ?? "")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)

            // Статистика
            HStack(spacing: 30) {
                VStack(spacing: 4) {
                    Text("\(gamesCount)")
                        .font(.title3.bold())
                    Text("Игр")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("—")
                            .font(.title3.bold())
                    }
                    Text("Рейтинг")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)

            // Игровые параметры
            VStack(alignment: .leading, spacing: 12) {
                Text("Игровые параметры")
                    .font(.headline)

                HStack {
                    parameterCard(
                        icon: "hand.raised",
                        title: "Хват",
                        value: userData["grip"] as? String ?? "—"
                    )
                    parameterCard(
                        icon: "figure.table.tennis",
                        title: "Стиль",
                        value: userData["playStyle"] as? String ?? "—"
                    )
                }
            }
            .padding(.horizontal)

            // Ссылка на рейтинг
            if let ratingLink = userData["ratingLink"] as? String, !ratingLink.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Рейтинг TTW")
                        .font(.headline)

                    Link(destination: URL(string: ratingLink) ?? URL(string: "https://r.ttw.ru")!) {
                        Label("Открыть на r.ttw.ru", systemImage: "link")
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()
        }
    }

    // MARK: - Экран "Пользователь недоступен"

    private var unavailableState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 70))
                .foregroundColor(.gray)

            Text("Пользователь недоступен")
                .font(.title3.bold())

            Text(isBlockedByMe
                 ? "Вы заблокировали этого игрока"
                 : "Профиль недоступен")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Кнопка разблокировки — только если это я заблокировал
            if isBlockedByMe {
                Button {
                    unblockUser()
                } label: {
                    Text("Разблокировать")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(isProcessingBlock)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 32)
    }

    // MARK: - Карточка параметра
    private func parameterCard(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.green)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Загрузка данных игрока
    private func loadPlayerData() {
        // Сначала проверяем блокировки
        BlockService.shared.loadBlocks {
            self.isBlockedByMe   = BlockService.shared.blockedUserIds.contains(self.userId)
            self.isBlockedByThem = BlockService.shared.blockedByUserIds.contains(self.userId)

            // Если недоступен — не грузим данные профиля
            if self.isUnavailable {
                self.isLoading = false
                return
            }

            self.fetchProfileData()
        }
    }

    private func fetchProfileData() {
        UserService.shared.fetchUser(id: userId) { data in
            self.userData = data ?? [:]
            self.isLoading = false
        }

        SparringService().countCompletedGames(userId: userId) { count in
            self.gamesCount = count
        }
    }

    // MARK: - Блокировка / Разблокировка

    private func blockUser() {
        isProcessingBlock = true
        BlockService.shared.block(userId: userId) { success in
            isProcessingBlock = false
            if success {
                isBlockedByMe = true
            }
        }
    }

    private func unblockUser() {
        isProcessingBlock = true
        BlockService.shared.unblock(userId: userId) { success in
            isProcessingBlock = false
            if success {
                isBlockedByMe = false
                // Перезагружаем данные профиля после разблокировки
                isLoading = true
                fetchProfileData()
            }
        }
    }
}
