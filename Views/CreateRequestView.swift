import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - CreateRequestView
// Экран создания новой заявки на спарринг
struct CreateRequestView: View {
    @ObservedObject var authService: AuthService
    
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var location = ""
    @State private var startTime = Calendar.current.date(from: DateComponents(hour: 18, minute: 0)) ?? Date()
    @State private var endTime = Calendar.current.date(from: DateComponents(hour: 20, minute: 0)) ?? Date()
    @State private var desiredLevel = "Любой"
    @State private var showSuccess = false
    @State private var isLoading = false
    
    // Состояния для показа пикеров времени (по одному за раз)
    @State private var showStartPicker = false
    @State private var showEndPicker = false
    
    let levels = ["Начинающий", "Любитель", "Продвинутый", "Профессионал", "Любой"]
    
    var minimumDate: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    // Форматирование времени для отображения
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Когда") {
                    DatePicker("Дата",
                               selection: $date,
                               in: minimumDate...,
                               displayedComponents: .date)
                    
                    // Начало — открывается как отдельный экран
                    HStack {
                        Text("Начало")
                        Spacer()
                        Button(formatTime(startTime)) {
                            showStartPicker = true
                        }
                        .foregroundColor(.green)
                    }
                    
                    // Конец — открывается как отдельный экран
                    HStack {
                        Text("Конец")
                        Spacer()
                        Button(formatTime(endTime)) {
                            showEndPicker = true
                        }
                        .foregroundColor(.green)
                    }
                }
                
                Section("Где") {
                    TextField("Место (клуб, адрес)", text: $location)
                }
                
                Section("Кого ищете") {
                    Picker("Желаемый уровень партнёра", selection: $desiredLevel) {
                        ForEach(levels, id: \.self) { Text($0) }
                    }
                }
                // Предупреждение если время конца раньше начала
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
                    .disabled(location.isEmpty || isLoading || endTime <= startTime)
                    .foregroundColor(.white)
                    .listRowBackground(Color.green)
                }
            }
            .navigationTitle("Новая заявка")
            // Модальное окно для выбора начала
            .sheet(isPresented: $showStartPicker) {
                TimePickerSheet(title: "Начало", time: $startTime, isPresented: $showStartPicker)
            }
            // Модальное окно для выбора конца
            .sheet(isPresented: $showEndPicker) {
                TimePickerSheet(title: "Конец", time: $endTime, isPresented: $showEndPicker)
            }
            .alert("Заявка опубликована!", isPresented: $showSuccess) {
                Button("OK") {
                    location = ""
                }
            } message: {
                Text("Другие игроки увидят вашу заявку в ленте")
            }
        }
    }
    
    // MARK: - Создание заявки в Firestore
    private func createRequest() {
        guard let userId = authService.currentUserId else { return }
        isLoading = true
        
        let db = Firestore.firestore()
        let timeSlot = "\(formatTime(startTime)) – \(formatTime(endTime))"
        
        let data: [String: Any] = [
            "userId": userId,
            "date": Timestamp(date: date),
            "timeSlot": timeSlot,
            "location": location,
            "desiredLevel": desiredLevel,
            "status": "active",
            "createdAt": Timestamp()
        ]
        
        db.collection("sparring_requests").addDocument(data: data) { error in
            DispatchQueue.main.async {
                isLoading = false
                if error == nil {
                    showSuccess = true
                }
            }
        }
    }
}

// MARK: - TimePickerSheet
// Отдельный экран-модалка для выбора времени
// Вынесен отдельно, чтобы избежать конфликтов DatePicker в Form
struct TimePickerSheet: View {
    let title: String
    @Binding var time: Date
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("",
                           selection: $time,
                           displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()
                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { isPresented = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(300)])  // Высота модалки
    }
}
