import Foundation

// MARK: - AdminConfig
// Список админов для встроенной модерации.
// В release-сборке админка скрыта через #if DEBUG в SettingsView.
// В др версии — заменить на веб-админку (admin.spinnet.app)
enum AdminConfig {
    static let adminUserIds: Set<String> = [
        "mGmw0uBqZTUOtIjr3hndu80Q4MF3"
    ]

    static func isAdmin(userId: String?) -> Bool {
        guard let userId = userId else { return false }
        return adminUserIds.contains(userId)
    }
}
