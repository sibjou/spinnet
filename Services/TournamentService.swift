import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - TournamentService
// Отвечает за всю логику работы с турнирами:
// создание, загрузка списка, запись участников, подтверждение явки
class TournamentService: ObservableObject {
    
    @Published var tournaments: [[String: Any]] = []  // Список турниров
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    private let db = Firestore.firestore()
    
    // MARK: - Создание турнира
    // Организатор заполняет форму → данные сохраняются в Firestore
    func createTournament(title: String, date: Date, location: String,
                          description: String, maxParticipants: Int,
                          organizerId: String, completion: @escaping (Bool) -> Void) {
        
        let data: [String: Any] = [
            "title": title,
            "date": Timestamp(date: date),
            "location": location,
            "description": description,
            "maxParticipants": maxParticipants,
            "organizerId": organizerId,
            "participants": [String](),           // Пустой массив — пока никто не записался
            "confirmedParticipants": [String](),  // Кто реально пришёл (заполняет организатор)
            "status": "upcoming",                 // upcoming → completed / cancelled
            "createdAt": Timestamp()
        ]
        
        db.collection("tournaments").addDocument(data: data) { error in
            DispatchQueue.main.async {
                completion(error == nil)
            }
        }
    }
    
    // MARK: - Загрузка турниров
    // Показываю индикатор загрузки только если турниров ещё нет
        // Если уже есть — обновляю тихо, без мигания экрана
        func loadTournaments() {
            if tournaments.isEmpty {
                isLoading = true
            }
        
        db.collection("tournaments")
            .whereField("status", isEqualTo: "upcoming")
            .order(by: "date", descending: false)  // Ближайшие сверху
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    guard let documents = snapshot?.documents else { return }
                    
                    // DispatchGroup — ждём загрузки всех имён организаторов
                    var loadedTournaments: [[String: Any]] = documents.map { doc in
                        var data = doc.data()
                        data["documentId"] = doc.documentID
                        return data
                    }
                    
                    let group = DispatchGroup()
                    
                    for (index, tournament) in loadedTournaments.enumerated() {
                        if let organizerId = tournament["organizerId"] as? String {
                            group.enter()
                            self?.db.collection("users").document(organizerId).getDocument { userDoc, _ in
                                if let userData = userDoc?.data() {
                                    let name = "\(userData["firstName"] ?? "") \(userData["lastName"] ?? "")"
                                    loadedTournaments[index]["organizerName"] = name
                                }
                                group.leave()
                            }
                        }
                    }
                    
                    group.notify(queue: .main) {
                        self?.tournaments = loadedTournaments
                    }
                }
            }
    }
    
    // MARK: - Записаться на турнир
    // Добавляет ID пользователя в массив participants
    func joinTournament(tournamentId: String, userId: String, completion: @escaping (Bool) -> Void) {
        // FieldValue.arrayUnion — добавляет элемент в массив, если его там ещё нет
        db.collection("tournaments").document(tournamentId).updateData([
            "participants": FieldValue.arrayUnion([userId])
        ]) { error in
            DispatchQueue.main.async {
                completion(error == nil)
            }
        }
    }
    
    // MARK: - Отменить участие
    func leaveTournament(tournamentId: String, userId: String, completion: @escaping (Bool) -> Void) {
        // FieldValue.arrayRemove — удаляет элемент из массива
        db.collection("tournaments").document(tournamentId).updateData([
            "participants": FieldValue.arrayRemove([userId])
        ]) { error in
            DispatchQueue.main.async {
                completion(error == nil)
            }
        }
    }
    
    // MARK: - Подтвердить участника (организатор)
    // В день турнира организатор отмечает кто реально пришёл
    func confirmParticipant(tournamentId: String, userId: String, completion: @escaping (Bool) -> Void) {
        db.collection("tournaments").document(tournamentId).updateData([
            "confirmedParticipants": FieldValue.arrayUnion([userId])
        ]) { error in
            DispatchQueue.main.async {
                completion(error == nil)
            }
        }
    }
    
    // MARK: - Завершить турнир
    func completeTournament(tournamentId: String, completion: @escaping (Bool) -> Void) {
        db.collection("tournaments").document(tournamentId).updateData([
            "status": "completed"
        ]) { error in
            DispatchQueue.main.async {
                completion(error == nil)
            }
        }
    }
}
