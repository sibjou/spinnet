import SwiftUI

// MARK: - LoginView
// Экран входа в приложение
struct LoginView: View {
    @Binding var showRegister: Bool
    @ObservedObject var authService: AuthService
    
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                // Логотип и название
                VStack(spacing: 8) {
                    Image(systemName: "sportscourt.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    Text("Spinnet")
                        .font(.largeTitle.bold())
                    Text("Найди спарринг-партнёра")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Поля ввода
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textFieldStyle(.roundedBorder)
                    
                    SecureField("Пароль", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)
                
                // Сообщение об ошибке
                if let error = authService.errorMessage {
                    Text(error)
                        .foregroundColor(error.contains("отправлено") ? .green : .red)
                        .font(.caption)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
                
                // Кнопка входа
                // .contentShape(Rectangle()) — делает ВСЮ область кнопки нажимаемой
                Button(action: { authService.login(email: email, password: password) }) {
                    if authService.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Войти").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(email.isEmpty || password.isEmpty ? Color.gray.opacity(0.3) : Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal)
                .contentShape(Rectangle()) //  Исправление бага 1: вся область кликабельна
                .disabled(email.isEmpty || password.isEmpty || authService.isLoading)
                
                // Забыли пароль
                Button("Забыли пароль?") {
                    if email.isEmpty {
                        authService.errorMessage = "Введите email выше, затем нажмите «Забыли пароль?»"
                    } else {
                        authService.resetPassword(email: email)
                    }
                }
                .foregroundColor(.secondary)
                .font(.caption)
                
                // Переход к регистрации
                // Исправление бага 2: очищаем ошибку при переходе
                Button("Нет аккаунта? Зарегистрироваться") {
                    authService.errorMessage = nil  // ← Сброс ошибки
                    showRegister = true
                }
                .foregroundColor(.green)
                
                Spacer()
            }
        }
    }
}
