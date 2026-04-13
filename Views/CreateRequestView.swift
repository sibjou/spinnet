import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - CreateRequestView
// Экран создания новой заявки на спарринг
struct CreateRequestView: View {
    @ObservedObject var authService: AuthService
    
    // Дата — минимум завтра (нельзя создать заявку в прошлом)
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var location = ""
    @State private var startTime = Calendar.current.date(from: DateComponents(hour: 18, minute: 0)) ?? Date()
    @State private var endTime = Calendar.current.date(from: DateComponents(hour: 20, minute: 0)) ?? Date()
    @State private var desiredLevel = "Любой"
    @State private var showSuccess = false
    @State private var isLoading = false
    
    let levels = ["Начинающий", "Любитель", "Продвинутый", "Профессионал", "Любой"]
    
    // Минимальная дата — завтра (чтобы нельзя было создать в прошлом)
    var minimumDate: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    // Форматирование времени для отображения
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: startTime)
        let end = formatter.string(from: endTime)
        return "\(start) – \(end)"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Когда") {
                    // Выбор даты — только начиная с сегодня
                    DatePicker("Дата",
                               selection: $date,
                               in: minimumDate...,  // ← Исправление бага 3: только будущие даты
                               displayedComponents: .date)
                    
                    // Выбор времени начала и конца
                    DatePicker("Начало",
                               selection: $startTime,
                               displayedComponents: .hourAndMinute)
                    
                    DatePicker("Конец",
                               selection: $endTime,
                               displayedComponents: .hourAndMinute)
                }
                
                Section("Где") {
                    TextField("Место (клуб, адрес)", text: $location)
                }
                
                Section("Кого ищете") {
                    Picker("Желаемый уровень партнёра", selection: $desiredLevel) {
                        ForEach(levels, id: \.self) { Text($0) }
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
                    .disabled(location.isEmpty || isLoading)
                    .foregroundColor(.white)
                    .listRowBackground(Color.green)
                }
            }
            .navigationTitle("Новая заявка")
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
        
        // Форматируем время для хранения
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeSlot = "\(formatter.string(from: startTime)) – \(formatter.string(from: endTime))"
        
        let data: [String: Any] = [
            "userId": userId,
            "date": Timestamp(date: date),          // Дата игры
            "timeSlot": timeSlot,                   // Время в формате "18:00 – 20:00"
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
