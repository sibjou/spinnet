import SwiftUI
import FirebaseFirestore

// MARK: - BookedGameDetailView
// Экран деталей забронированной игры
// Показывает: партнёра, место, время
// Действия: отменить участие (чат добавим позже)
struct BookedGameDetailView: View {
    let game: [String: Any]
    @ObservedObject var authService: AuthService
    @ObservedObject var sparringService: SparringService
    @Binding var isPresented: Bool
    
    @State private var partnerName: String = "Загрузка..."
    @State private var partnerSkill: String = ""
    @State private var partnerCity: String = ""
    @State private var isLoadingPartner = true
    @State private var isProcessing = false
    @State private var showCancelConfirm = false
    
    // Форматирование даты
    var formattedDate: String {
        guard let timestamp = game["date"] as? Timestamp else { return "Дата не указана" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy, EEEE"
        return formatter.string(from: timestamp.dateValue())
    }
    
    // Определяю ID партнёра (не моего)
    var partnerId: String? {
        guard let userId = authService.currentUserId else { return nil }
        let authorId = game["userId"] as? String
        let bookedById = game["bookedBy"] as? String
        
        // Партнёр — это тот, кто НЕ я
        if authorId == userId {
            return bookedById
        } else {
            return authorId
        }
    }
    
    // Моя роль в этой игре
    var myRole: String {
        game["userId"] as? String == authService.currentUserId ? "автор заявки" : "забронировал"
    }
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Информация о партнёре
                Section("С кем играете") {
                    if isLoadingPartner {
                        HStack {
                            ProgressView()
                            Text("Загрузка...")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(partnerName)
                                    .fontWeight(.semibold)
                                Text("\(partnerSkill) • \(partnerCity)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // MARK: - Детали встречи
                Section("Детали встречи") {
                    Label(formattedDate, systemImage: "calendar")
                    Label(game["timeSlot"] as? String ?? "", systemImage: "clock")
                    Label(game["location"] as? String ?? "", systemImage: "mappin.circle.fill")
                }
                
                // MARK: - Ваша роль
                Section("Ваша роль") {
                    Label("Вы: \(myRole)", systemImage: "person.fill.checkmark")
                        .foregroundColor(.secondary)
                }
                
                // MARK: - Чат уточнений (заглушка)
                Section {
                    Button(action: {}) {
                        Label("Открыть чат уточнений", systemImage: "bubble.left.and.bubble.right")
                    }
                    .disabled(true)
                } footer: {
                    Text("Чат с вариантами ответов будет доступен в следующем обновлении")
                        .font(.caption)
                }
                
                // MARK: - Отмена участия
                Section {
                    Button("Отменить участие", role: .destructive) {
                        showCancelConfirm = true
                    }
                    .disabled(isProcessing)
                } footer: {
                    Text("Заявка вернётся в общую ленту, партнёр получит уведомление (в разработке)")
                        .font(.caption)
                }
            }
            .navigationTitle("Предстоящая игра")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") { isPresented = false }
                }
            }
            .alert("Отменить участие?", isPresented: $showCancelConfirm) {
                Button("Нет", role: .cancel) {}
                Button("Отменить", role: .destructive) { cancelAction() }
            } message: {
                Text("Заявка вернётся в общую ленту, и другие игроки смогут на неё откликнуться")
            }
            .onAppear { loadPartnerInfo() }
        }
    }
    
    // MARK: - Загрузка информации о партнёре
    private func loadPartnerInfo() {
        guard let id = partnerId, !id.isEmpty else {
            partnerName = "Партнёр не найден"
            isLoadingPartner = false
            return
        }
        
        Firestore.firestore().collection("users").document(id).getDocument { doc, _ in
            DispatchQueue.main.async {
                if let data = doc?.data() {
                    let firstName = data["firstName"] as? String ?? ""
                    let lastName = data["lastName"] as? String ?? ""
                    self.partnerName = "\(firstName) \(lastName)"
                    self.partnerSkill = data["skillLevel"] as? String ?? ""
                    self.partnerCity = data["city"] as? String ?? ""
                } else {
                    self.partnerName = "Пользователь удалён"
                }
                self.isLoadingPartner = false
            }
        }
    }
    
    // MARK: - Отмена бронирования
    private func cancelAction() {
        guard let requestId = game["documentId"] as? String,
              let userId = authService.currentUserId else { return }
        isProcessing = true
        
        sparringService.cancelBooking(requestId: requestId) { success in
            isProcessing = false
            if success {
                // Обновляю данные профиля
                sparringService.loadAll(userId: userId)
                isPresented = false
            }
        }
    }
}
