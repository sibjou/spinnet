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
    @State private var ratingLink = ""
    @FocusState private var focusedField: Field?

    private enum Field { case firstName, lastName, email, password }

    private var missingFields: [String] {
        RegistrationRules.missing(email: email, password: password,
                                  firstName: firstName, lastName: lastName, city: city)
    }

    let levels = ["Начинающий", "Любитель", "Продвинутый", "Профессионал"]
    let grips = ["Шейкхолд", "Пенхолд"]
    let styles = ["Нападающий", "Защитник", "Комбинированный"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                    SecureField("Пароль", text: $password)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .firstName }
                } header: {
                    Text("Вход")
                } footer: {
                    Text("Пароль — не короче 6 символов")
                }

                Section("О вас") {
                    TextField("Имя", text: $firstName)
                        .textContentType(.givenName)
                        .focused($focusedField, equals: .firstName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .lastName }
                    TextField("Фамилия", text: $lastName)
                        .textContentType(.familyName)
                        .focused($focusedField, equals: .lastName)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                    CityRow(city: $city)
                }

                Section {
                    Picker("Уровень игры", selection: $selectedLevel) {
                        ForEach(levels, id: \.self) { Text($0) }
                    }
                    Picker("Хват ракетки", selection: $selectedGrip) {
                        ForEach(grips, id: \.self) { Text($0) }
                    }
                    Picker("Стиль игры", selection: $selectedStyle) {
                        ForEach(styles, id: \.self) { Text($0) }
                    }
                } header: {
                    Text("Как вы играете")
                } footer: {
                    Text("Это увидят партнёры в заявках. Позже можно изменить в профиле.")
                }

                Section {
                    TextField("https://r.ttw.ru/players/?id=...", text: $ratingLink)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                } header: {
                    Text("Рейтинг TTW (необязательно)")
                } footer: {
                    Text("Вставьте ссылку на ваш профиль с сайта r.ttw.ru")
                        .font(.caption)
                }
                
                // Ошибка — показываем ТОЛЬКО если она появилась на экране регистрации
                if let error = authService.errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(AppColor.danger)
                            .font(.footnote)
                    }
                }
                
                Section {
                    Button(action: {
                        // Валидация ссылки на рейтинг (если указана)
                        if !ratingLink.isEmpty && !isValidRatingLink(ratingLink) {
                            authService.errorMessage = "Ссылка должна вести на r.ttw.ru"
                            return
                        }
                        
                        authService.register(
                            email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password,
                            firstName: firstName.trimmingCharacters(in: .whitespaces),
                            lastName: lastName.trimmingCharacters(in: .whitespaces),
                            city: city, skillLevel: selectedLevel,
                            grip: selectedGrip, playStyle: selectedStyle,
                            ratingLink: ratingLink
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
                    .disabled(!missingFields.isEmpty || authService.isLoading)
                    .foregroundColor(.white)
                    .listRowBackground(missingFields.isEmpty ? AppColor.primary : Color(.systemGray3))
                } footer: {
                    // Почему кнопка не нажимается: ровно то, чего не хватает
                    if let hint = RegistrationRules.hint(for: missingFields) {
                        Text(hint)
                    }
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
    // MARK: - Проверка ссылки на рейтинг
    private func isValidRatingLink(_ link: String) -> Bool {
        guard let url = URL(string: link),
              let host = url.host else { return false }
        let allowedHosts = ["r.ttw.ru", "www.r.ttw.ru"]
        return allowedHosts.contains(host.lowercased())
    }
}
