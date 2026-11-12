import Foundation

// MARK: - Разделы профиля, которые можно скрыть
enum ProfileSection {
    case stats          // вкладка «Статистика»
    case matchHistory   // список матчей и личные встречи с соперниками
    case tournaments    // вкладка «Турниры»
}

// MARK: - Настройки приватности
// Хранятся в users/{uid}.privacy. Если поля нет — всё открыто.
// Сейчас ограничения применяются в приложении; жёсткая проверка на сервере появится
// вместе с собственным бэкендом.
struct PrivacySettings: Equatable {
    var showStats = true
    var showMatchHistory = true
    var showTournaments = true
    var allowClarifications = true      // партнёры по игре могут писать уточнения
    var showLastSeen = true             // показывать, что я в сети, и когда был(а) в сети

    static let `default` = PrivacySettings()

    init() {}

    /// `userData` — документ users/{uid}
    init(userData: [String: Any]?) {
        let map = userData?["privacy"] as? [String: Any] ?? [:]
        showStats           = map["showStats"]           as? Bool ?? true
        showMatchHistory    = map["showMatchHistory"]    as? Bool ?? true
        showTournaments     = map["showTournaments"]     as? Bool ?? true
        allowClarifications = map["allowClarifications"] as? Bool ?? true
        showLastSeen        = map["showLastSeen"]        as? Bool ?? true
    }

    var firestoreMap: [String: Bool] {
        [
            "showStats":           showStats,
            "showMatchHistory":    showMatchHistory,
            "showTournaments":     showTournaments,
            "allowClarifications": allowClarifications,
            "showLastSeen":        showLastSeen
        ]
    }

    /// Владелец видит всё, остальные — только разрешённое
    func canView(_ section: ProfileSection, isOwner: Bool) -> Bool {
        if isOwner { return true }
        switch section {
        case .stats:        return showStats
        case .matchHistory: return showStats && showMatchHistory
        case .tournaments:  return showTournaments
        }
    }
}
