import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct CreateRequestView: View {
    @ObservedObject var authService: AuthService

    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var location = ""
    @State private var city = ""                   // ← НОВОЕ
    @State private var startTime = Calendar.current.date(from: DateComponents(hour: 18, minute: 0)) ?? Date()
    @State private var endTime   = Calendar.current.date(from: DateComponents(hour: 20, minute: 0)) ?? Date()
    @State private var desiredLevel = "Любой"
    @State private var showSuccess = false
    @State private var isLoading = false
    @State private var showStartPicker = false
    @State private var showEndPicker = false
    @State private var showCityPicker = false      // ← НОВОЕ

    let levels = ["Начинающий", "Любитель", "Продвинутый", "Профессионал", "Любой"]

    var minimumDate: Date { Calendar.current.startOfDay(for: Date()) }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Когда") {
                    DatePicker("Дата", selection: $date, in: minimumDate..., displayedComponents: .date)

                    HStack {
                        Text("Начало")
                        Spacer()
                        Button(formatTime(startTime)) { showStartPicker = true }
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("Конец")
                        Spacer()
                        Button(formatTime(endTime)) { showEndPicker = true }
                            .foregroundColor(.green)
                    }
                }

                Section("Где") {
                    // Город — отдельное поле для фильтрации
                    HStack {
                        Text("Город")
                        Spacer()
                        Button(city.isEmpty ? "Выбрать" : city) { showCityPicker = true }
                            .foregroundColor(city.isEmpty ? .secondary : .primary)
                    }

                    TextField("Место (клуб, адрес)", text: $location)
                }

                Section("Кого ищете") {
                    Picker("Желаемый уровень партнёра", selection: $desiredLevel) {
                        ForEach(levels, id: \.self) { Text($0) }
                    }
                }

                if endTime <= startTime {
                    Section {
                        Label("Время конца должно быть позже начала", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button(action: createRequest) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Опубликовать заявку")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(location.isEmpty || city.isEmpty || isLoading || endTime <= startTime)
                    .foregroundColor(.white)
                    .listRowBackground(Color.green)
                }
            }
            .navigationTitle("Новая заявка")
            .sheet(isPresented: $showStartPicker) {
                TimePickerSheet(title: "Начало", time: $startTime, isPresented: $showStartPicker)
            }
            .sheet(isPresented: $showEndPicker) {
                TimePickerSheet(title: "Конец", time: $endTime, isPresented: $showEndPicker)
            }
            .sheet(isPresented: $showCityPicker) {
                CityPickerView(selectedCity: $city, isPresented: $showCityPicker)
            }
            .alert("Заявка опубликована!", isPresented: $showSuccess) {
                Button("OK") { location = "" }
            } message: {
                Text("Другие игроки увидят вашу заявку в ленте")
            }
            .onAppear {
                // Подставляем город из профиля по умолчанию
                if city.isEmpty, let profileCity = authService.userProfile?.city {
                    city = profileCity
                }
            }
        }
    }

    private func createRequest() {
        guard let userId = authService.currentUserId,
              let profile = authService.userProfile else { return }

        isLoading = true
        let timeSlot = "\(formatTime(startTime)) – \(formatTime(endTime))"

        // Денормализация: сохраняем данные автора прямо в заявке
        // Это убирает N+1 запросы в ленте
        let data: [String: Any] = [
            "userId":           userId,
            "authorFirstName":  profile.firstName,
            "authorLastName":   profile.lastName,
            "authorSkillLevel": profile.skillLevel,
            "authorGrip":       profile.grip,
            "authorPlayStyle":  profile.playStyle,
            "date":             Timestamp(date: date),
            "timeSlot":         timeSlot,
            "city":             city,
            "location":         location,
            "desiredLevel":     desiredLevel,
            "status":           "active",
            "createdAt":        Timestamp()
        ]

        SparringService().createRequest(data: data) { success in
            isLoading = false
            if success { showSuccess = true }
        }
    }
}
