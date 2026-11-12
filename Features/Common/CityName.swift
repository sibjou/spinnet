import Foundation

// MARK: - CityName
// Город в Firestore — просто строка, а набрана она бывает по-разному: «Мурманск», «Мурманск » (пробел в конце),
// «мурманск», «Мурманска», «Mурманск» (первая буква латинская). Человек видит один город,
// а сравнение строк — пять разных, из-за чего в фильтре истории и появлялись дубли.
// Здесь все такие варианты сводятся к одному названию. Чистая логика: проверяется тестами.

enum CityName {

    // MARK: Ключ сравнения

    /// Строка, по которой города сравниваются: без регистра, лишних пробелов и знаков,
    /// с одинаковыми дефисами, «е» вместо «ё», без невидимых символов, без «г.» в начале;
    /// латинские буквы, похожие на русские, заменены (если в названии есть хоть одна русская).
    static func key(_ raw: String) -> String {
        words(raw).joined(separator: " ")
    }

    // MARK: Название

    /// Как показывать город и под каким именем его хранить.
    /// - название из списка приложения (`CityData`), если город узнаётся — и с другим окончанием
    ///   (до двух букв): «Мурманска», «Томске», «Москвы»;
    /// - иначе то, что ввели, но без лишних пробелов и невидимых символов, с заглавной буквы.
    static func canonical(_ raw: String) -> String {
        let normalized = key(raw)
        guard !normalized.isEmpty else { return "" }
        if let name = knownByKey[normalized] { return name }
        if let name = closeKnownName(for: normalized) { return name }
        return tidy(raw)
    }

    /// Один и тот же город, как бы он ни был написан
    static func same(_ first: String, _ second: String) -> Bool {
        groupKey(first) == groupKey(second)
    }

    /// Ключ для группировки игр и заявок по городам
    static func groupKey(_ raw: String) -> String {
        key(canonical(raw))
    }

    // MARK: Внутри

    private static let known: [(key: String, name: String)] = CityData.allCities.map { (key($0), $0) }

    private static let knownByKey: [String: String] = {
        var result: [String: String] = [:]
        for entry in known { result[entry.key] = entry.name }
        return result
    }()

    /// Русские буквы, на которые похожи латинские (после перевода в нижний регистр)
    private static let lookalikes: [Character: Character] = [
        "a": "а", "b": "в", "c": "с", "e": "е", "h": "н", "k": "к",
        "m": "м", "o": "о", "p": "р", "t": "т", "x": "х", "y": "у"
    ]

    private static func words(_ raw: String) -> [String] {
        var text = ""
        for scalar in raw.lowercased().unicodeScalars {
            switch scalar.value {
            case 0x0451: text.append("е")        // ё
            case 0x0439: text.append("и")        // й (в одной записи или «и» + значок — одинаково)
            default:
                let category = scalar.properties.generalCategory
                if category == .format || category == .nonspacingMark {
                    continue                      // невидимые символы и значки над буквами
                }
                if scalar.properties.isAlphabetic || (0x30...0x39).contains(scalar.value) {
                    text.unicodeScalars.append(scalar)
                } else {
                    text.append(" ")              // пробелы, дефисы, точки, запятые — разделители
                }
            }
        }

        let hasCyrillic = text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
        if hasCyrillic {
            text = String(text.map { lookalikes[$0] ?? $0 })
        }

        var parts = text.split(separator: " ").map(String.init)
        // «г. Томск», «город Томск»
        if parts.count > 1, parts[0] == "г" || parts[0] == "город" {
            parts.removeFirst()
        }
        return parts
    }

    /// Город из списка приложения, от названия которого введённое отличается только окончанием
    /// (до двух букв): «Мурманска», «Москвы», «Томске». Если подходит больше одного города — не гадаем.
    private static func closeKnownName(for typedKey: String) -> String? {
        let typed = Array(typedKey)
        var found: String?
        for entry in known {
            let candidate = Array(entry.key)
            var common = 0
            while common < min(typed.count, candidate.count), typed[common] == candidate[common] {
                common += 1
            }
            guard common >= 4,
                  typed.count - common <= 2, candidate.count - common <= 2,
                  typed[common...].allSatisfy({ $0.isLetter }),
                  candidate[common...].allSatisfy({ $0.isLetter }) else { continue }
            if let existing = found, existing != entry.name { return nil }
            found = entry.name
        }
        return found
    }

    /// Введённое как есть, но аккуратно: один вид дефиса и пробела, без невидимых символов, с заглавной буквы
    private static func tidy(_ raw: String) -> String {
        var text = ""
        for scalar in raw.unicodeScalars {
            let category = scalar.properties.generalCategory
            if category == .format { continue }
            if category == .dashPunctuation || scalar.value == 0x2212 {
                text.append("-")
            } else if scalar.properties.isWhitespace {
                text.append(" ")
            } else {
                text.unicodeScalars.append(scalar)
            }
        }
        let collapsed = text.split(separator: " ").joined(separator: " ")
        guard let first = collapsed.first else { return "" }
        return first.uppercased() + String(collapsed.dropFirst())
    }
}
