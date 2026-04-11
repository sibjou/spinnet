import SwiftUI
import FirebaseFirestore

struct FeedView: View {
    @ObservedObject var authService: AuthService
    @State private var requests: [[String: Any]] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Загрузка...")
                } else if requests.isEmpty {
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
                    List(requests.indices, id: \.self) { index in
                        let req = requests[index]
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.green)
                                VStack(alignment: .leading) {
                                    Text(req["userName"] as? String ?? "Игрок")
                                        .fontWeight(.semibold)
                                    Text("Ищет: \(req["desiredLevel"] as? String ?? "")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Text("📍 \(req["location"] as? String ?? "")")
                                .font(.subheadline)
                            Text("🕐 \(req["timeSlot"] as? String ?? "")")
                                .font(.subheadline)
                            
                            if req["userId"] as? String != authService.currentUserId {
                                Button("Сыграть") {}
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Спарринги")
            .onAppear { loadRequests() }
            .refreshable { loadRequests() }
        }
    }
    
    private func loadRequests() {
        let db = Firestore.firestore()
        db.collection("sparring_requests")
            .whereField("status", isEqualTo: "active")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false
                    guard let documents = snapshot?.documents else { return }
                    
                    self.requests = documents.map { doc in
                        var data = doc.data()
                        data["documentId"] = doc.documentID
                        return data
                    }
                    
                    // Подгружаем имена пользователей
                    for (index, req) in self.requests.enumerated() {
                        if let userId = req["userId"] as? String {
                            db.collection("users").document(userId).getDocument { userDoc, _ in
                                if let userData = userDoc?.data() {
                                    let name = "\(userData["firstName"] ?? "") \(userData["lastName"] ?? "")"
                                    DispatchQueue.main.async {
                                        if index < self.requests.count {
                                            self.requests[index]["userName"] = name
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
    }
}
