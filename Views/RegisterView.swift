import SwiftUI

// MARK: - RegisterView
// Экран регистрации нового пользователя
struct RegisterView: View {
    @Binding var showRegister: Bool
    @ObservedObject var authService: AuthService
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var city = ""
    @State private var selectedLevel = "Любитель"
    @State private var selectedGrip = "Шейкхолд"
    @State private var selectedStyle = "Комбинированный"
    
    let levels = ["Начинающий", "Любитель", "Продвинутый", "Профессионал"]
    let grips = ["Шейкхолд", "Пенхолд"]
    let styles = ["Нападающий", "Защитник", "Комбинированный"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Личные данные") {
                    TextField("Имя", text: $firstName)
                    TextField("Фамилия", text: $lastName)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    SecureField("Пароль (минимум 6 символов)", text: $password)
                    TextField("Город", text: $city)
                }
                
                Section("Игровые параметры") {
                    Picker("Уровень игры", selection: $selectedLevel) {
                        ForEach(levels, id: \.self) { Text($0) }
                    }
                    Picker("Хват ракетки", selection: $selectedGrip) {
                        ForEach(grips, id: \.self) { Text($0) }
                    }
                    Picker("Стиль игры", selection: $selectedStyle) {
                        ForEach(styles, id: \.self) { Text($0) }
                    }
                }
                
                // Ошибка — показываем ТОЛЬКО если она появилась на экране регистрации
                if let error = authService.errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section {
                    Button(action: {
                        authService.register(
                            email: email, password: password,
                            firstName: firstName, lastName: lastName,
                            city: city, skillLevel: selectedLevel,
                            grip: selectedGrip, playStyle: selectedStyle
                        )
                    }) {
                        if authService.isLoading {
                            ProgressView()
                        } else {
                            Text("Зарегистрироваться")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(firstName.isEmpty || email.isEmpty || password.count < 6 || authService.isLoading)
                    .foregroundColor(.white)
                    .listRowBackground(Color.green)
                }
            }
            .navigationTitle("Регистрация")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Назад") {
                        authService.errorMessage = nil  // ← Сброс ошибки при возврате
                        showRegister = false
                    }
                }
            }
            // Сбрасываем ошибку при появлении экрана
            .onAppear {
                authService.errorMessage = nil
            }
        }
    }
}
