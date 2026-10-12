import Foundation
import Combine
import FirebaseFirestore

final class TournamentViewModel: ObservableObject {

    @Published var displayedTournaments: [[String: Any]] = []
    @Published var isLoading = false

    // Город — серверный фильтр
    // Свободные места и статус — клиентские
    @Published var filterCity     = "Все города"   { didSet { if oldValue != filterCity { loadFromServer() } } }
    @Published var filterOnlyFree = false           { didSet { applyClientFilters() } }

    var hasActiveFilters: Bool {
        filterCity != "Все города" || filterOnlyFree
    }

    private let db = Firestore.firestore()
    private var allTournaments: [[String: Any]] = []

    func loadFromServer() {
        isLoading = true

        var query: Query = db.collection("tournaments")
            .whereField("status", in: ["upcoming", "in_progress"])

        if filterCity != "Все города" {
            query = query.whereField("city", isEqualTo: filterCity)
        }

        query = query.order(by: "date", descending: false)

        query.getDocuments { [weak self] snapshot, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    print("TournamentViewModel error: \(error.localizedDescription)")
                    return
                }
                self?.allTournaments = snapshot?.documents.map { doc in
                    var data = doc.data()
                    data["documentId"] = doc.documentID
                    return data
                } ?? []
                self?.applyClientFilters()
            }
        }
    }

    private func applyClientFilters() {
        displayedTournaments = allTournaments.filter { t in
            if filterOnlyFree {
                let count = (t["participants"] as? [String])?.count ?? 0
                let max   = t["maxParticipants"] as? Int ?? 0
                if max > 0 && count >= max { return false }
            }
            return true
        }
    }

    func resetFilters() {
        filterOnlyFree = false
        filterCity     = "Все города"  // последним — запустит loadFromServer()
    }
}
