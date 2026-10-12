import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

class TournamentService: ObservableObject {

    @Published var tournaments: [[String: Any]] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    private let db = Firestore.firestore()

    // MARK: - Создание турнира
    // organizerName и city — денормализованные поля, убирают N+1 запросы
    func createTournament(title: String, date: Date, startTime: String,
                          endDate: Date, endTime: String,
                          city: String, location: String, description: String,
                          maxParticipants: Int, organizerId: String,
                          organizerName: String,
                          completion: @escaping (Bool) -> Void) {

        let data: [String: Any] = [
            "title": title,
            "date": Timestamp(date: date),
            "startTime": startTime,
            "endDate": Timestamp(date: endDate),
            "endTime": endTime,
            "city": city,
            "location": location,
            "description": description,
            "maxParticipants": maxParticipants,
            "organizerId": organizerId,
            "organizerName": organizerName,
            "participants": [String](),
            "confirmedParticipants": [String](),
            "status": "upcoming",
            "createdAt": Timestamp()
        ]

        db.collection("tournaments").addDocument(data: data) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    func updateTournament(tournamentId: String, title: String, date: Date,
                          startTime: String, endDate: Date, endTime: String,
                          city: String, location: String,
                          description: String, maxParticipants: Int,
                          completion: @escaping (Bool) -> Void) {

        let updateData: [String: Any] = [
            "title": title,
            "date": Timestamp(date: date),
            "startTime": startTime,
            "endDate": Timestamp(date: endDate),
            "endTime": endTime,
            "city": city,
            "location": location,
            "description": description,
            "maxParticipants": maxParticipants
        ]

        db.collection("tournaments").document(tournamentId).updateData(updateData) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    // MARK: - Удаление турнира
    func deleteTournament(tournamentId: String, completion: @escaping (Bool) -> Void) {
        db.collection("tournaments").document(tournamentId).delete { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    // MARK: - Загрузка турниров (без N+1)
    func loadTournaments() {
        if tournaments.isEmpty { isLoading = true }

        db.collection("tournaments")
            .whereField("status", in: ["upcoming", "in_progress"])
            .order(by: "date", descending: false)
            .getDocuments { [weak self] snapshot, _ in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    guard let documents = snapshot?.documents else { return }

                    // organizerName уже в документе — запрос в users не нужен
                    self?.tournaments = documents.map { doc in
                        var data = doc.data()
                        data["documentId"] = doc.documentID
                        return data
                    }
                }
            }
    }

    // MARK: - Запись / отмена участия
    func joinTournament(tournamentId: String, userId: String, completion: @escaping (Bool) -> Void) {
        db.collection("tournaments").document(tournamentId).updateData([
            "participants": FieldValue.arrayUnion([userId])
        ]) { error in DispatchQueue.main.async { completion(error == nil) } }
    }

    func leaveTournament(tournamentId: String, userId: String, completion: @escaping (Bool) -> Void) {
        db.collection("tournaments").document(tournamentId).updateData([
            "participants": FieldValue.arrayRemove([userId])
        ]) { error in DispatchQueue.main.async { completion(error == nil) } }
    }

    // MARK: - Управление участниками (организатор)
    func confirmParticipant(tournamentId: String, userId: String, completion: @escaping (Bool) -> Void) {
        db.collection("tournaments").document(tournamentId).updateData([
            "confirmedParticipants": FieldValue.arrayUnion([userId])
        ]) { error in DispatchQueue.main.async { completion(error == nil) } }
    }

    func unconfirmParticipant(tournamentId: String, userId: String, completion: @escaping (Bool) -> Void) {
        db.collection("tournaments").document(tournamentId).updateData([
            "confirmedParticipants": FieldValue.arrayRemove([userId])
        ]) { error in DispatchQueue.main.async { completion(error == nil) } }
    }

    func removeParticipant(tournamentId: String, userId: String, completion: @escaping (Bool) -> Void) {
        db.collection("tournaments").document(tournamentId).updateData([
            "participants": FieldValue.arrayRemove([userId]),
            "confirmedParticipants": FieldValue.arrayRemove([userId])
        ]) { error in DispatchQueue.main.async { completion(error == nil) } }
    }

    func completeTournament(tournamentId: String, completion: @escaping (Bool) -> Void) {
        db.collection("tournaments").document(tournamentId).updateData([
            "status": "completed"
        ]) { error in DispatchQueue.main.async { completion(error == nil) } }
    }
}
