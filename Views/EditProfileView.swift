import SwiftUI
import FirebaseFirestore

// MARK: - EditProfileView
// Экран редактирования своего профиля
// Пользователь может изменить: имя, фамилию, город, уровень, хват, стиль, ссылку на рейтинг
struct EditProfileView: View {
    @ObservedObject var authService: AuthService
    @Binding var isPresented: Bool
    let onUpdate: () -> Void
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var city = ""
    @State private var skillLevel = "Любитель"
    @State private var grip = "Шейкхолд"
    @State private var playStyle = "Комбинированный"
    @State private var ratingLink = ""
    
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    let levels = ["Начинающий", "Любитель", "Продвинутый", "Профессионал"]
    let grips = ["Шейкхолд", "Пенхолд"]
    let styles = ["Нападающий", "Защитник", "Комбинированный"]
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Form {
                        Section("Личные данные") {
                            TextField("Имя", text: $firstName)
                            TextField("Фамилия", text: $lastName)
                            TextField("Город", text: $city)
                        }
                        
                        Section("Игровые параметры") {
                            Picker("Уровень игры", selection: $skillLevel) {
                                ForEach(levels, id: \.self) { Text($0) }
                            }
                            Picker("Хват ракетки", selection: $grip) {
                                ForEach(grips, id: \.self) { Text($0) }
                            }
                            Picker("Стиль игры", selection: $playStyle) {
                                ForEach(styles, id: \.self) { Text($0) }
                            }
                        }
                        
                        Section {
                            TextField("Ссылка на ваш профиль на r.ttw.ru", text: $ratingLink)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                        } header: {
                            Text("Рейтинг TTW")
                        } footer: {
                            Text("Необязательно. Укажите ссылку на свой профиль в рейтинге настольного тенниса")
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { isPresented = false }
                        .foregroundColor(.red)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") { saveChanges() }
                        .fontWeight(.semibold)
                        .disabled(firstName.isEmpty || lastName.isEmpty || city.isEmpty || isSaving)
                }
            }
            .alert("Ошибка", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear { loadProfile() }
        }
    }
    
    // MARK: - Загрузка текущих данных профиля
    private func loadProfile() {
        guard let userId = authService.currentUserId else { return }
        
        Firestore.firestore().collection("users").document(userId).getDocument { doc, _ in
            DispatchQueue.main.async {
                if let data = doc?.data() {
                    self.firstName = data["firstName"] as? String ?? ""
                    self.lastName = data["lastName"] as? String ?? ""
                    self.city = data["city"] as? String ?? ""
                    self.skillLevel = data["skillLevel"] as? String ?? "Любитель"
                    self.grip = data["grip"] as? String ?? "Шейкхолд"
                    self.playStyle = data["playStyle"] as? String ?? "Комбинированный"
                    self.ratingLink = data["ratingLink"] as? String ?? ""
                }
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Сохранение изменений
    private func saveChanges() {
        guard let userId = authService.currentUserId else { return }
        isSaving = true
        
        let updateData: [String: Any] = [
            "firstName": firstName,
            "lastName": lastName,
            "city": city,
            "skillLevel": skillLevel,
            "grip": grip,
            "playStyle": playStyle,
            "ratingLink": ratingLink
        ]
        
        Firestore.firestore().collection("users").document(userId).updateData(updateData) { error in
            DispatchQueue.main.async {
                isSaving = false
                if let error = error {
                    errorMessage = "Не удалось сохранить: \(error.localizedDescription)"
                    showError = true
                } else {
                    onUpdate()
                    isPresented = false
                }
            }
        }
    }
}
