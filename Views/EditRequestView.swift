import SwiftUI
import FirebaseFirestore

// MARK: - EditRequestView
// Экран редактирования существующей заявки
// Открывается из профиля при нажатии на свою активную заявку
struct EditRequestView: View {
    let requestId: String
    @Binding var isPresented: Bool
    let onUpdate: () -> Void
    
    @State private var date = Date()
    @State private var location = ""
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var desiredLevel = "Любой"
    
    @State private var showStartPicker = false
    @State private var showEndPicker = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    
    let levels = ["Начинающий", "Любитель", "Продвинутый", "Профессионал", "Любой"]
    
    var minimumDate: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Form {
                        Section("Когда") {
                            DatePicker("Дата",
                                       selection: $date,
                                       in: minimumDate...,
                                       displayedComponents: .date)
                            
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
                            TextField("Место", text: $location)
                        }
                        
                        Section("Кого ищете") {
                            Picker("Желаемый уровень", selection: $desiredLevel) {
                                ForEach(levels, id: \.self) { Text($0) }
                            }
                        }
                        
                        // Кнопка удаления заявки
                        Section {
                            Button("Удалить заявку", role: .destructive) {
                                showDeleteConfirm = true
                            }
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
                        .disabled(location.isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showStartPicker) {
                TimePickerSheet(title: "Начало", time: $startTime, isPresented: $showStartPicker)
            }
            .sheet(isPresented: $showEndPicker) {
                TimePickerSheet(title: "Конец", time: $endTime, isPresented: $showEndPicker)
            }
            .alert("Удалить заявку?", isPresented: $showDeleteConfirm) {
                Button("Отмена", role: .cancel) {}
                Button("Удалить", role: .destructive) { deleteRequest() }
            } message: {
                Text("Заявка будет удалена безвозвратно")
            }
            .onAppear { loadRequest() }
        }
    }
    
    // MARK: - Загрузка данных заявки для редактирования
    private func loadRequest() {
        Firestore.firestore().collection("sparring_requests").document(requestId).getDocument { doc, _ in
            DispatchQueue.main.async {
                if let data = doc?.data() {
                    self.location = data["location"] as? String ?? ""
                    self.desiredLevel = data["desiredLevel"] as? String ?? "Любой"
                    
                    if let timestamp = data["date"] as? Timestamp {
                        self.date = timestamp.dateValue()
                    }
                    
                    // Парсим время из строки "18:00 – 20:00"
                    if let timeSlot = data["timeSlot"] as? String {
                        let parts = timeSlot.components(separatedBy: " – ")
                        if parts.count == 2 {
                            self.startTime = self.parseTime(parts[0]) ?? Date()
                            self.endTime = self.parseTime(parts[1]) ?? Date()
                        }
                    }
                }
                self.isLoading = false
            }
        }
    }
    
    // Вспомогательная функция: строка "18:00" → Date
    private func parseTime(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: string)
    }
    
    // MARK: - Сохранение изменений
    private func saveChanges() {
        isSaving = true
        let timeSlot = "\(formatTime(startTime)) – \(formatTime(endTime))"
        
        let updateData: [String: Any] = [
            "date": Timestamp(date: date),
            "timeSlot": timeSlot,
            "location": location,
            "desiredLevel": desiredLevel
        ]
        
        Firestore.firestore().collection("sparring_requests").document(requestId).updateData(updateData) { error in
            DispatchQueue.main.async {
                isSaving = false
                if error == nil {
                    onUpdate()
                    isPresented = false
                }
            }
        }
    }
    
    // MARK: - Удаление заявки
    private func deleteRequest() {
        Firestore.firestore().collection("sparring_requests").document(requestId).delete { error in
            DispatchQueue.main.async {
                if error == nil {
                    onUpdate()
                    isPresented = false
                }
            }
        }
    }
}
