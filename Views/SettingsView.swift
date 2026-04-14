import SwiftUI

// MARK: - SettingsView
// Экран настроек (открывается по нажатию на три полоски)
// Тут: выход из аккаунта, информация о приложении и др.
struct SettingsView: View {
    @ObservedObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Аккаунт") {
                    // Email текущего пользователя
                    Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(.red)
                        .onTapGesture {
                            authService.logout()
                            dismiss()
                        }
                }
                
                Section("О приложении") {
                    Label("Версия: 1.0.0", systemImage: "info.circle")
                    Label("Spinnet", systemImage: "sportscourt")
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
