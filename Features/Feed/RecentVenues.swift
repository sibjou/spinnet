import Foundation

// MARK: - Недавние места
// Большинство людей играют в одних и тех же залах. Последние места подставляются под полем «Место» одним касанием:
// не нужно каждый раз набирать адрес, а «Зал ТПУ» и «зал тпу» не превращаются в два разных места.

enum RecentVenues {

    /// Сколько мест помнить
    nonisolated static let limit = 5

    /// Ключ в UserDefaults: у каждого аккаунта на телефоне свой список
    static func storageKey(userId: String) -> String { "venues.recent.\(userId)" }

    /// Список после добавления места: новое — первым, повтор (без учёта регистра и лишних пробелов) переезжает наверх
    static func updated(_ list: [String], adding venue: String, limit: Int = RecentVenues.limit) -> [String] {
        let cleaned = tidy(venue)
        guard !cleaned.isEmpty else { return list }
        var result = [cleaned]
        for item in list where !same(item, cleaned) {
            result.append(item)
        }
        return Array(result.prefix(limit))
    }

    /// Подсказки под полем: недавние места, которые подходят к набранному тексту и не совпадают с ним целиком
    static func suggestions(_ list: [String], typed: String) -> [String] {
        let query = fold(typed)
        return list.filter { item in
            let folded = fold(item)
            if folded == query { return false }
            return query.isEmpty || folded.contains(query)
        }
    }

    // MARK: Внутри

    private static func tidy(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func fold(_ text: String) -> String {
        tidy(text).lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    private static func same(_ first: String, _ second: String) -> Bool {
        fold(first) == fold(second)
    }
}
