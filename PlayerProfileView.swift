import SwiftUI
import FirebaseFirestore

// MARK: - PlayerProfileView
// Экран просмотра профиля другого игрока
// Открывается при нажатии на имя в ленте или в турнире
struct PlayerProfileView: View {
    let userId: String
    
    @State private var userData: [String: Any] = [:]
    @State private var isLoading = true
    @State private var gamesCount = 0
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding(.top, 50)
            } else {
                VStack(spacing: 20) {
                    // Аватарка и имя
                    VStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)
                        
                        Text("\(userData["firstName"] as? String ?? "") \(userData["lastName"] as? String ?? "")")
                            .font(.title2.bold())
                        
                        Text("\(userData["skillLevel"] as? String ?? "") • \(userData["city"] as? String ?? "")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Статистика
                    HStack(spacing: 30) {
                        // Количество игр
                        VStack(spacing: 4) {
                            Text("\(gamesCount)")
                                .font(.title3.bold())
                            Text("Игр")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Рейтинг (заглушка пока нет отзывов)
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
                    
                    // Ссылка на рейтинг (если указана)
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
        }
        .navigationTitle("Профиль игрока")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadPlayerData() }
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
        let db = Firestore.firestore()
        
        // Загружаю профиль
        db.collection("users").document(userId).getDocument { doc, _ in
            DispatchQueue.main.async {
                self.userData = doc?.data() ?? [:]
                self.isLoading = false
            }
        }
        
        // Считаю количество завершённых игр
        db.collection("sparring_requests")
            .whereField("status", isEqualTo: "completed")
            .getDocuments { snapshot, _ in
                DispatchQueue.main.async {
                    let count = snapshot?.documents.filter { doc in
                        let data = doc.data()
                        return data["userId"] as? String == userId ||
                               data["bookedBy"] as? String == userId
                    }.count ?? 0
                    self.gamesCount = count
                }
            }
    }
}
