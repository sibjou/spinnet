import Foundation

// MARK: - Правила регистрации
// Кнопка «Зарегистрироваться» неактивна, пока что-то не заполнено. Чтобы человек не гадал, что именно,
// под кнопкой пишется, чего не хватает.

enum RegistrationRules {

    static let minPasswordLength = 6

    /// Похоже на адрес почты: что-то до «@», точка в домене, без пробелов. Точную проверку делает сервер.
    static func looksLikeEmail(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(" ") else { return false }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    /// Чего не хватает, в порядке заполнения формы. Пусто — можно регистрироваться.
    static func missing(email: String,
                        password: String,
                        firstName: String,
                        lastName: String,
                        city: String) -> [String] {
        var result: [String] = []
        if !looksLikeEmail(email) { result.append("почта") }
        if password.count < minPasswordLength { result.append("пароль от \(minPasswordLength) символов") }
        if firstName.trimmingCharacters(in: .whitespaces).isEmpty { result.append("имя") }
        if lastName.trimmingCharacters(in: .whitespaces).isEmpty { result.append("фамилия") }
        if city.trimmingCharacters(in: .whitespaces).isEmpty { result.append("город") }
        return result
    }

    /// Подсказка под кнопкой; nil — всё заполнено
    static func hint(for missing: [String]) -> String? {
        missing.isEmpty ? nil : "Осталось заполнить: " + missing.joined(separator: ", ")
    }
}
