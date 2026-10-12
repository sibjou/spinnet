import SwiftUI

// MARK: - SettingsView
// Экран настроек: аккаунт, приватность, уведомления, поддержка, о приложении
struct SettingsView: View {
    @ObservedObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var showLogoutConfirm = false

    private let appVersion = "1.0.0"
    private let supportEmail = "support@spinnet.app"

    var body: some View {
        NavigationStack {
            List {

                // MARK: - Аккаунт
                Section("Аккаунт") {
                    NavigationLink {
                        EditProfileView(
                            authService: authService,
                            isPresented: .constant(true),
                            onUpdate: {}
                        )
                    } label: {
                        Label("Редактировать профиль", systemImage: "person.crop.circle")
                    }
                }

                // MARK: - Конфиденциальность и безопасность
                Section("Конфиденциальность и безопасность") {
                    NavigationLink {
                        BlockedUsersView()
                    } label: {
                        Label("Заблокированные пользователи", systemImage: "hand.raised")
                    }
                }

                // MARK: - Поддержка
                Section("Поддержка") {
                    Button {
                        contactSupport()
                    } label: {
                        Label("Связаться с поддержкой", systemImage: "envelope")
                    }
                    .foregroundColor(.primary)

                    Button {
                        reportProblem()
                    } label: {
                        Label("Сообщить о проблеме", systemImage: "exclamationmark.bubble")
                    }
                    .foregroundColor(.primary)
                }

                // MARK: - Модерация (только для админа в debug-сборке)
                #if DEBUG
                if AdminConfig.isAdmin(userId: authService.currentUserId) {
                    Section("Модерация") {
                        NavigationLink {
                            AdminPanelView()
                        } label: {
                            Label("Панель модератора", systemImage: "shield.lefthalf.filled")
                                .foregroundColor(AppColor.warning)
                        }
                    }

                    Section("Разработка") {
                        Button("Тест уведомления") {
                            NotificationService.shared.sendTestNotification()
                        }
                    }
                }
                #endif

                // MARK: - О приложении
                Section("О приложении") {
                    HStack {
                        Label("Версия", systemImage: "info.circle")
                        Spacer()
                        Text(appVersion).foregroundColor(.secondary)
                    }
                    // Политика и Условия — пока заглушки, добавим ссылки перед публикацией
                    // Link("Политика конфиденциальности", destination: URL(string: "https://spinnet.app/privacy")!)
                    // Link("Условия использования", destination: URL(string: "https://spinnet.app/terms")!)
                }

                // MARK: - Выход
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .alert("Выйти из аккаунта?", isPresented: $showLogoutConfirm) {
                Button("Отмена", role: .cancel) {}
                Button("Выйти", role: .destructive) {
                    authService.logout()
                    dismiss()
                }
            }
        }
    }

    // MARK: - Поддержка

    private func contactSupport() {
        let subject = "Spinnet — Обращение в поддержку"
        openMail(subject: subject, body: "")
    }

    private func reportProblem() {
        let subject = "Spinnet — Сообщение о проблеме"
        let body = "Опишите проблему:\n\n\n———\nВерсия приложения: \(appVersion)"
        openMail(subject: subject, body: body)
    }

    private func openMail(subject: String, body: String) {
        let s = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let b = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(supportEmail)?subject=\(s)&body=\(b)") {
            UIApplication.shared.open(url)
        }
    }
}
