import SwiftUI
import FirebaseFirestore

// MARK: - EditProfileView
// Экран редактирования своего профиля.
// Имя и фамилия меняются не чаще раза в 30 дней — защита от мошенничества
// и поддержание консистентности денормализованных данных.
struct EditProfileView: View {
    @ObservedObject var authService: AuthService
    @Binding var isPresented: Bool
    let onUpdate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var city = ""
    @State private var skillLevel = "Любитель"
    @State private var grip = "Шейкхолд"
    @State private var playStyle = "Комбинированный"
    @State private var ttwRating: String = ""
    @State private var ratingLink: String = ""

    // Исходные значения — чтобы понять что изменилось
    @State private var originalFirstName = ""
    @State private var originalLastName = ""
    @State private var originalSkillLevel = ""
    @State private var originalGrip = ""
    @State private var originalPlayStyle = ""

    // Дата последнего изменения имени
    @State private var lastNameChangeAt: Date? = nil

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    let levels = ["Начинающий", "Любитель", "Продвинутый", "Профессионал"]
    let grips = ["Шейкхолд", "Пенхолд"]
    let styles = ["Нападающий", "Защитник", "Комбинированный"]

    private let nameChangeCooldownDays = 30

    private var canChangeName: Bool {
        guard let last = lastNameChangeAt else { return true }
        let nextAllowed = Calendar.current.date(byAdding: .day, value: nameChangeCooldownDays, to: last) ?? last
        return Date() >= nextAllowed
    }

    private var nextNameChangeDate: Date? {
        guard let last = lastNameChangeAt else { return nil }
        return Calendar.current.date(byAdding: .day, value: nameChangeCooldownDays, to: last)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Form {
                        Section {
                            TextField("Имя", text: $firstName)
                                .disabled(!canChangeName)
                                .foregroundColor(canChangeName ? .primary : .secondary)
                            TextField("Фамилия", text: $lastName)
                                .disabled(!canChangeName)
                                .foregroundColor(canChangeName ? .primary : .secondary)
                            TextField("Город", text: $city)
                        } header: {
                            Text("Личные данные")
                        } footer: {
                            if !canChangeName, let date = nextNameChangeDate {
                                Text("Имя и фамилию можно изменить после \(formattedDate(date))")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Text("Имя и фамилию можно менять не чаще раза в 30 дней")
                                    .font(.caption)
                            }
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
                            HStack {
                                Text("Числовой рейтинг")
                                Spacer()
                                TextField("0", text: $ttwRating)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                            }

                            TextField("https://r.ttw.ru/players/?id=...", text: $ratingLink)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                        } header: {
                            Text("Рейтинг TTW")
                        } footer: {
                            Text("Введите числовой рейтинг (например 1850) и ссылку на ваш профиль с сайта r.ttw.ru. Это поможет партнёрам оценить ваш уровень.")
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { dismiss() }
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
                    self.firstName  = data["firstName"]  as? String ?? ""
                    self.lastName   = data["lastName"]   as? String ?? ""
                    self.city       = data["city"]       as? String ?? ""
                    self.skillLevel = data["skillLevel"] as? String ?? "Любитель"
                    self.grip       = data["grip"]       as? String ?? "Шейкхолд"
                    self.playStyle  = data["playStyle"]  as? String ?? "Комбинированный"
                    self.ratingLink = data["ratingLink"] as? String ?? ""

                    self.originalFirstName  = self.firstName
                    self.originalLastName   = self.lastName
                    self.originalSkillLevel = self.skillLevel
                    self.originalGrip       = self.grip
                    self.originalPlayStyle  = self.playStyle

                    if let ts = data["lastNameChangeAt"] as? Timestamp {
                        self.lastNameChangeAt = ts.dateValue()
                    }

                    let rating = data["ttwRating"] as? Int ?? 0
                    self.ttwRating = rating > 0 ? "\(rating)" : ""
                }
                self.isLoading = false
            }
        }
    }

    // MARK: - Сохранение изменений
    private func saveChanges() {
        guard let userId = authService.currentUserId else { return }

        if !ratingLink.isEmpty && !isValidRatingLink(ratingLink) {
            errorMessage = "Ссылка должна вести на r.ttw.ru. Пример: https://r.ttw.ru/players/?id=123abc"
            showError = true
            return
        }

        let nameChanged = (firstName != originalFirstName) || (lastName != originalLastName)
        let paramsChanged = (skillLevel != originalSkillLevel) ||
                            (grip != originalGrip) ||
                            (playStyle != originalPlayStyle)
        let needsDenormUpdate = nameChanged || paramsChanged

        if nameChanged && !canChangeName {
            errorMessage = "Имя и фамилию можно изменить только раз в 30 дней"
            showError = true
            return
        }

        isSaving = true

        let ttwValue = Int(ttwRating) ?? 0

        var updateData: [String: Any] = [
            "firstName":  firstName,
            "lastName":   lastName,
            "city":       city,
            "skillLevel": skillLevel,
            "grip":       grip,
            "playStyle":  playStyle,
            "ratingLink": ratingLink,
            "ttwRating":  ttwValue
        ]

        if nameChanged {
            updateData["lastNameChangeAt"] = Timestamp()
        }

        Firestore.firestore().collection("users").document(userId).updateData(updateData) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Ошибка сохранения профиля: \(error.localizedDescription)")
                    isSaving = false
                    errorMessage = "Не удалось сохранить: \(error.localizedDescription)"
                    showError = true
                    return
                }

                print("✅ Профиль сохранён в users")

                // Профиль сохранён — закрываем окно сразу.
                // Обновление копий идёт в фоне и не блокирует закрытие.
                isSaving = false
                onUpdate()
                dismiss()

                if needsDenormUpdate {
                    self.updateDenormalizedData(userId: userId) {
                        print("✅ Денормализованные копии обновлены")
                    }
                }
            }
        }
    }

    // MARK: - Обновление денормализованных данных
    // Обновляем копии в активных/забронированных заявках и предстоящих турнирах.
    // История (завершённые игры) не трогается — хранит данные на момент игры.
    private func updateDenormalizedData(userId: String, completion: @escaping () -> Void) {
        let db = Firestore.firestore()
        let group = DispatchGroup()

        group.enter()
        db.collection("sparring_requests")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", in: ["active", "booked", "in_progress"])
            .getDocuments { snapshot, _ in
                if let docs = snapshot?.documents, !docs.isEmpty {
                    let batch = db.batch()
                    for doc in docs {
                        batch.updateData([
                            "authorFirstName":  self.firstName,
                            "authorLastName":   self.lastName,
                            "authorSkillLevel": self.skillLevel,
                            "authorGrip":       self.grip,
                            "authorPlayStyle":  self.playStyle
                        ], forDocument: doc.reference)
                    }
                    batch.commit { _ in group.leave() }
                } else {
                    group.leave()
                }
            }

        group.enter()
        db.collection("tournaments")
            .whereField("organizerId", isEqualTo: userId)
            .whereField("status", in: ["upcoming", "in_progress"])
            .getDocuments { snapshot, _ in
                if let docs = snapshot?.documents, !docs.isEmpty {
                    let batch = db.batch()
                    for doc in docs {
                        batch.updateData([
                            "organizerName": "\(self.firstName) \(self.lastName)"
                        ], forDocument: doc.reference)
                    }
                    batch.commit { _ in group.leave() }
                } else {
                    group.leave()
                }
            }

        group.notify(queue: .main) {
            completion()
        }
    }

    // MARK: - Проверка ссылки на рейтинг
    private func isValidRatingLink(_ link: String) -> Bool {
        guard let url = URL(string: link),
              let host = url.host else { return false }

        let allowedHosts = ["r.ttw.ru", "www.r.ttw.ru"]
        return allowedHosts.contains(host.lowercased())
    }

    // MARK: - Формат даты
    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }
}
