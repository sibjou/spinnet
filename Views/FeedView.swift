import SwiftUI
import FirebaseFirestore

// MARK: - FeedView
// Экран ленты спарринг-заявок
// Показывает все активные заявки от других игроков
struct FeedView: View {
    @ObservedObject var authService: AuthService
    
    // Массив заявок — каждая заявка это словарь [ключ: значение]
    @State private var requests: [[String: Any]] = []
    @State private var isLoading = true
    @State private var showBookingAlert = false
    @State private var bookingMessage = ""
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    // Пока данные грузятся — показываем индикатор
                    ProgressView("Загрузка...")
                } else if requests.isEmpty {
                    // Если заявок нет — показываем заглушку
                    VStack(spacing: 12) {
                        Image(systemName: "sportscourt")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("Пока нет заявок")
                            .foregroundColor(.secondary)
                        Text("Создайте первую заявку!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Список заявок
                    List(requests.indices, id: \.self) { index in
                        RequestCardView(
                            request: requests[index],
                            isOwnRequest: requests[index]["userId"] as? String == authService.currentUserId,
                            onBook: {
                                bookRequest(at: index)
                            }
                        )
                    }
                }
            }
            .navigationTitle("Спарринги")
            // onAppear — вызывается когда экран появляется на экране
            .onAppear { loadRequests() }
            // refreshable — позволяет обновить свайпом вниз
            .refreshable { loadRequests() }
            // alert — всплывающее окно с результатом бронирования
            .alert("Бронирование", isPresented: $showBookingAlert) {
                Button("OK") {}
            } message: {
                Text(bookingMessage)
            }
        }
    }
    
    // MARK: - Загрузка заявок из Firestore
    // Загружает все заявки со статусом "active", сортирует по дате создания (новые сверху)
    // Затем для каждой заявки подгружает имя автора из коллекции "users"
    private func loadRequests() {
        let db = Firestore.firestore()
        
        db.collection("sparring_requests")
            .whereField("status", isEqualTo: "active")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false
                    guard let documents = snapshot?.documents else { return }
                    
                    // Фильтрую: свои заявки не показываю
                    var loadedRequests: [[String: Any]] = documents.compactMap { doc in
                        let data = doc.data()
                        // Если это моя заявка — пропускаю
                        if data["userId"] as? String == authService.currentUserId {
                            return nil
                        }
                        var result = data
                        result["documentId"] = doc.documentID
                        return result
                    }
                    
                    // Для каждой заявки сразу подгружаем имя автора
                    let group = DispatchGroup()  // Группа для ожидания всех запросов
                    
                    for (index, req) in loadedRequests.enumerated() {
                        if let userId = req["userId"] as? String {
                            group.enter()  // Входим в группу (ещё один запрос)
                            
                            db.collection("users").document(userId).getDocument { userDoc, _ in
                                if let userData = userDoc?.data() {
                                    let firstName = userData["firstName"] as? String ?? ""
                                    let lastName = userData["lastName"] as? String ?? ""
                                    let skillLevel = userData["skillLevel"] as? String ?? ""
                                    let grip = userData["grip"] as? String ?? ""
                                    
                                    loadedRequests[index]["userName"] = "\(firstName) \(lastName)"
                                    loadedRequests[index]["userSkill"] = skillLevel
                                    loadedRequests[index]["userGrip"] = grip
                                }
                                group.leave()  // Выходим из группы (запрос завершён)
                            }
                        }
                    }
                    
                    // Когда ВСЕ имена загружены — обновляем экран одним разом
                    // Это исправляет мигание "Игрок"
                    group.notify(queue: .main) {
                        self.requests = loadedRequests
                    }
                }
            }
    }
    
    // MARK: - Бронирование заявки
    // Когда пользователь нажимает "Сыграть":
    // 1. Статус заявки меняется на "booked"
    // 2. Сохраняется ID того, кто забронировал
    private func bookRequest(at index: Int) {
        guard let documentId = requests[index]["documentId"] as? String,
              let userId = authService.currentUserId else { return }
        
        let db = Firestore.firestore()
        
        // Обновляем документ в Firestore
        db.collection("sparring_requests").document(documentId).updateData([
            "status": "booked",                // Меняем статус
            "bookedBy": userId,                // Кто забронировал
            "bookedAt": Timestamp()            // Когда забронировал
        ]) { error in
            DispatchQueue.main.async {
                if let error = error {
                    bookingMessage = "Ошибка: \(error.localizedDescription)"
                } else {
                    bookingMessage = "Вы забронировали спарринг! Игрок получит уведомление."
                    // Убираем заявку из ленты (она больше не active)
                    requests.remove(at: index)
                }
                showBookingAlert = true
            }
        }
    }
}
