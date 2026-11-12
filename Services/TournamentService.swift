import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

class TournamentService: ObservableObject {

    /// Растёт после каждого изменения турнира (запись, отмена, подтверждение, завершение…).
    /// Экраны, которые показывают турниры пользователя, перечитывают список, когда число меняется.
    @Published private(set) var changeCounter = 0

    private let db = Firestore.firestore()

    private func reportChange(_ success: Bool) {
        if success { changeCounter += 1 }
    }

    // MARK: - Создание турнира
    // organizerName и city — денормализованные поля, убирают N+1 запросы
    func createTournament(title: String, date: Date, startTime: String,
                          endDate: Date, endTime: String,
                          city: String, location: String, description: String,
                          maxParticipants: Int, organizerId: String,
                          organizerName: String,
                          completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }

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

        db.collection("tournaments").addDocument(data: data) { [weak self] error in
            DispatchQueue.main.async {
                self?.reportChange(error == nil)
                completion(error == nil)
            }
        }
    }

    func updateTournament(tournamentId: String, title: String, date: Date,
                          startTime: String, endDate: Date, endTime: String,
                          city: String, location: String,
                          description: String, maxParticipants: Int,
                          completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }

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

        db.collection("tournaments").document(tournamentId).updateData(updateData) { [weak self] error in
            DispatchQueue.main.async {
                self?.reportChange(error == nil)
                completion(error == nil)
            }
        }
    }

    // MARK: - Удаление турнира
    func deleteTournament(tournamentId: String, completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }
        db.collection("tournaments").document(tournamentId).delete { [weak self] error in
            DispatchQueue.main.async {
                self?.reportChange(error == nil)
                completion(error == nil)
            }
        }
    }

    // MARK: - Запись / отмена участия
    func joinTournament(tournamentId: String, userId: String, completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }
        db.collection("tournaments").document(tournamentId).updateData([
            "participants": FieldValue.arrayUnion([userId])
        ]) { [weak self] error in
            DispatchQueue.main.async {
                self?.reportChange(error == nil)
                completion(error == nil)
            }
        }
    }

    func leaveTournament(tournamentId: String, userId: String, completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }
        db.collection("tournaments").document(tournamentId).updateData([
            "participants": FieldValue.arrayRemove([userId])
        ]) { [weak self] error in
            DispatchQueue.main.async {
                self?.reportChange(error == nil)
                completion(error == nil)
            }
        }
    }

    // MARK: - Управление участниками (организатор)
    func confirmParticipant(tournamentId: String, userId: String, completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }
        db.collection("tournaments").document(tournamentId).updateData([
            "confirmedParticipants": FieldValue.arrayUnion([userId])
        ]) { [weak self] error in
            DispatchQueue.main.async {
                self?.reportChange(error == nil)
                completion(error == nil)
            }
        }
    }

    func unconfirmParticipant(tournamentId: String, userId: String, completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }
        db.collection("tournaments").document(tournamentId).updateData([
            "confirmedParticipants": FieldValue.arrayRemove([userId])
        ]) { [weak self] error in
            DispatchQueue.main.async {
                self?.reportChange(error == nil)
                completion(error == nil)
            }
        }
    }

    func removeParticipant(tournamentId: String, userId: String, completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }
        db.collection("tournaments").document(tournamentId).updateData([
            "participants": FieldValue.arrayRemove([userId]),
            "confirmedParticipants": FieldValue.arrayRemove([userId])
        ]) { [weak self] error in
            DispatchQueue.main.async {
                self?.reportChange(error == nil)
                completion(error == nil)
            }
        }
    }

    func completeTournament(tournamentId: String, completion: @escaping (Bool) -> Void) {
        guard ConnectionMonitor.shared.allowWrite(otherwise: completion) else { return }
        db.collection("tournaments").document(tournamentId).updateData([
            "status": "completed"
        ]) { [weak self] error in
            DispatchQueue.main.async {
                self?.reportChange(error == nil)
                completion(error == nil)
            }
        }
    }

    // MARK: - Один турнир
    func fetchTournament(id: String, completion: @escaping ([String: Any]?) -> Void) {
        db.collection("tournaments").document(id).getDocument { doc, _ in
            DispatchQueue.main.async {
                guard var data = doc?.data() else {
                    completion(nil)
                    return
                }
                data["documentId"] = doc?.documentID
                completion(data)
            }
        }
    }

    // MARK: - Турниры пользователя
    // Два точечных запроса вместо чтения всей коллекции:
    // где он участник и где он организатор (любой статус).
    func loadUserTournaments(userId: String,
                             completion: @escaping (_ participating: [[String: Any]],
                                                    _ organizing: [[String: Any]]) -> Void) {
        let group = DispatchGroup()
        var participating: [[String: Any]] = []
        var organizing: [[String: Any]] = []

        func mapped(_ snapshot: QuerySnapshot?) -> [[String: Any]] {
            snapshot?.documents.map { doc in
                var data = doc.data()
                data["documentId"] = doc.documentID
                return data
            } ?? []
        }

        group.enter()
        db.collection("tournaments")
            .whereField("participants", arrayContains: userId)
            .getDocuments { snapshot, _ in
                participating = mapped(snapshot)
                group.leave()
            }

        group.enter()
        db.collection("tournaments")
            .whereField("organizerId", isEqualTo: userId)
            .getDocuments { snapshot, _ in
                organizing = mapped(snapshot)
                group.leave()
            }

        group.notify(queue: .main) { completion(participating, organizing) }
    }
}
