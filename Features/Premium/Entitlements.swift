import Foundation

// MARK: - Тариф
enum Plan: String {
    case free
    case pro

    init(raw: String?) {
        self = Plan(rawValue: raw ?? "") ?? .free
    }
}

// MARK: - Функции, которые в будущем могут стать платными
enum Feature: String, CaseIterable {
    case statsOverview      // сводка: матчи, победы, форма
    case statsCharts        // графики активности и динамики
    case statsHeatmap       // тепловая карта «когда играете»
    case statsHeadToHead    // личные встречи с соперниками

    /// Минимальный тариф для функции
    var requiredPlan: Plan {
        switch self {
        case .statsOverview: return .free
        case .statsCharts, .statsHeatmap, .statsHeadToHead: return .pro
        }
    }

    var title: String {
        switch self {
        case .statsOverview:   return "Сводка статистики"
        case .statsCharts:     return "Графики активности и динамики"
        case .statsHeatmap:    return "Тепловая карта игр"
        case .statsHeadToHead: return "Личные встречи с соперниками"
        }
    }
}

// MARK: - Единая точка проверки доступа
// Пока подписки нет, `paywallEnabled == false`, и всё доступно всем.
// Когда подключим оплату — достаточно включить флаг; экраны менять не придётся.
enum FeatureGate {

    /// Включить, когда появится подписка (StoreKit)
    nonisolated static let paywallEnabled = false

    static func isAvailable(_ feature: Feature,
                            plan: Plan,
                            paywallEnabled: Bool = FeatureGate.paywallEnabled) -> Bool {
        guard paywallEnabled else { return true }
        switch feature.requiredPlan {
        case .free: return true
        case .pro:  return plan == .pro
        }
    }
}
