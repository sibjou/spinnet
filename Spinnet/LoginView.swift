import SwiftUI

struct LoginView: View {
    @Binding var showRegister: Bool
    @ObservedObject var authService: AuthService
    
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                VStack(spacing: 8) {
                    Image(systemName: "sportscourt.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    Text("PongMatch")
                        .font(.largeTitle.bold())
                    Text("Найди спарринг-партнёра")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textFieldStyle(.roundedBorder)
                    
                    SecureField("Пароль", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)
                
                if let error = authService.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                Button(action: { authService.login(email: email, password: password) }) {
                    if authService.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Войти").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal)
                .disabled(email.isEmpty || password.isEmpty || authService.isLoading)
                
                Button("Нет аккаунта? Зарегистрироваться") {
                    showRegister = true
                }
                .foregroundColor(.green)
                
                Spacer()
            }
        }
    }
}
