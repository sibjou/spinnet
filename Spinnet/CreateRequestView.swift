import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct CreateRequestView: View {
    @ObservedObject var authService: AuthService
    
    @State private var date = Date()
    @State private var location = ""
    @State private var timeSlot = "Вечер (18:00-21:00)"
    @State private var desiredLevel = "Любитель"
    @State private var showSuccess = false
    @State private var isLoading = false
    
    let timeSlots = ["Утро (8:00-12:00)", "День (12:00-17:00)", "Вечер (18:00-21:00)"]
    let levels = ["Начинающий", "Любитель", "Продвинутый", "Профессионал", "Любой"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Когда и где") {
                    DatePicker("Дата", selection: $date, displayedComponents: .date)
                    Picker("Время", selection: $timeSlot) {
                        ForEach(timeSlots, id: \.self) { Text($0) }
                    }
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
    
    private func createRequest() {
        guard let userId = authService.currentUserId else { return }
        isLoading = true
        
        let db = Firestore.firestore()
        
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
