import Foundation

// MARK: - Модуль модерации контента
// Локальная проверка отзывов:
// - Запрещённые слова (мат, угрозы, спам)
// - Удаление персональных данных (телефоны, email, ссылки)
//
// Roadmap: интеграция с Yandex SpeechKit Modero для ML-анализа

enum ContentModeration {

    // MARK: - Запрещённые слова (корни)
    // Проверяем по корням — ловит вариации

    /// Мат, оскорбления, угрозы, дискриминация — недопустимо нигде, в том числе в переписке
    private static let abusiveRoots: Set<String> = [
        // Мат и оскорбления
        "хуй", "хуё", "хуи", "пизд", "пизж",
        "ебан", "ебат", "ёбан", "ёбат", "ебал",
        "блядь", "блят", "бляд",
        "сука", "суки", "суче",
        "пидор", "пидар", "педр", "пидр",
        "хер", "херн",
        "мраз", "ублюд", "урод", "тварь",
        "гондон", "пизде", "ебуч",

        // Угрозы и насилие
        "убью", "убит", "убийц", "сдохн", "сдох",
        "размаж", "выруб", "грохн",

        // Дискриминация
        "хохол", "москал", "чурк", "негр",
        "жидов", "жид "
    ]

    /// Реклама и призывы уйти в другие мессенджеры: лишнее в публичных отзывах,
    /// но в личной переписке двух игроков это обычное дело («пиши в телеграм»)
    private static let spamRoots: Set<String> = [
        "телеграм", "telegram", "@t.me",
        "whatsapp", "ватсап", "ватсаб", "вотсап",
        "viber", "вайбер",
        "instagram", "инстаграм", "инст ",
        "vk.com", "вк.ком",
        "купи", "продам", "скидк", "акци"
    ]

    private static let forbiddenRoots: Set<String> = abusiveRoots.union(spamRoots)

    // MARK: - Результат проверки
    enum Verdict {
        case approved              // всё ок, публикуем
        case needsReview(reason: String)  // на ручную модерацию
    }

    // MARK: - Полная проверка комментария
    // Возвращает очищенный текст + статус модерации
    static func process(_ text: String) -> (cleanedText: String, verdict: Verdict) {
        // Сначала очищаем персональные данные
        let cleaned = sanitize(text)

        // Затем проверяем на запрещённые слова
        let verdict = check(cleaned)

        return (cleaned, verdict)
    }

    // MARK: - Сообщение в личной переписке
    // Только мат, угрозы и оскорбления. Контакты и ссылки не вырезаются:
    // люди договариваются о встрече и сами решают, чем делиться.
    static func isAcceptableMessage(_ text: String) -> Bool {
        if case .approved = check(text, roots: abusiveRoots) { return true }
        return false
    }

    // MARK: - Проверка на запрещённые слова
    private static func check(_ text: String, roots: Set<String>? = nil) -> Verdict {
        if text.isEmpty { return .approved }

        let lower = text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")  // нормализация

        for root in roots ?? forbiddenRoots {
            let normalizedRoot = root.replacingOccurrences(of: "ё", with: "е")
            if lower.contains(normalizedRoot) {
                return .needsReview(reason: "Обнаружены недопустимые выражения")
            }
        }

        return .approved
    }

    // MARK: - Очистка персональных данных
    // Вырезает телефоны, email, ссылки, ники соцсетей
    private static func sanitize(_ text: String) -> String {
        var result = text

        // Телефоны: +7..., 8..., 7..., с пробелами/дефисами/скобками
        result = replace(in: result,
                         pattern: #"[\+]?[78][\s\-\(\)]?\d{3}[\s\-\(\)]?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}"#,
                         with: "[номер скрыт]")

        // Email
        result = replace(in: result,
                         pattern: #"[\w\.\-]+@[\w\.\-]+\.\w+"#,
                         with: "[email скрыт]")

        // URLs
        result = replace(in: result,
                         pattern: #"https?://\S+|www\.\S+|t\.me/\S+"#,
                         with: "[ссылка скрыта]")

        // Telegram ники @username
        result = replace(in: result,
                         pattern: #"@[a-zA-Z0-9_]{5,}"#,
                         with: "[контакт скрыт]")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Утилита: regex-замена
    private static func replace(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }
}
