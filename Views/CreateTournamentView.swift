import SwiftUI

// MARK: - CreateTournamentView
// Экран создания нового турнира
struct CreateTournamentView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var tournamentService: TournamentService
    @Binding var isPresented: Bool
    
    @State private var title = ""
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var startTime = Calendar.current.date(from: DateComponents(hour: 10, minute: 0)) ?? Date()
    @State private var location = ""
    @State private var description = ""
    @State private var maxParticipants = 16
    @State private var isLoading = false
    @State private var showSuccess = false
    
    @State private var showStartPicker = false
    
    var minimumDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }
    
    let participantOptions = [4, 8, 12, 16, 24, 32, 64]
    
    // Форматирование времени для отображения
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Основная информация") {
                    TextField("Название турнира", text: $title)
                    
                    DatePicker("Дата проведения",
                               selection: $date,
                               in: minimumDate...,
                               displayedComponents: .date)
                    
                    // Время начала турнира — отдельная модалка
                    HStack {
                        Text("Время начала")
                        Spacer()
                        Button(formatTime(startTime)) { showStartPicker = true }
                            .foregroundColor(.green)
                    }
                    
                    TextField("Место проведения", text: $location)
                }
                
                Section("Детали") {
                    Picker("Макс. участников", selection: $maxParticipants) {
                        ForEach(participantOptions, id: \.self) { num in
                            Text("\(num) чел.").tag(num)
                        }
                    }
                }
                
                Section {
                    TextField("Формат, правила, призы...", text: $description)
                        .onChange(of: description) { _, newValue in
                            if newValue.count > 300 {
                                description = String(newValue.prefix(300))
                            }
                        }
                } header: {
                    Text("Описание")
                } footer: {
                    Text("\(description.count)/300 символов")
                        .foregroundColor(description.count >= 280 ? .red : .secondary)
                }
                
                Section {
                    Button(action: createTournament) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Создать турнир")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(title.isEmpty || location.isEmpty || isLoading)
                    .foregroundColor(.white)
                    .listRowBackground(Color.green)
                }
            }
            .navigationTitle("Новый турнир")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { isPresented = false }
                        .foregroundColor(.red)
                }
            }
            .sheet(isPresented: $showStartPicker) {
                TimePickerSheet(title: "Время начала", time: $startTime, isPresented: $showStartPicker)
            }
            .alert("Турнир создан!", isPresented: $showSuccess) {
                Button("OK") {
                    isPresented = false
                    tournamentService.loadTournaments()
                }
            } message: {
                Text("Игроки увидят ваш турнир в списке")
            }
        }
    }
    
    // MARK: - Создание турнира в Firestore
    private func createTournament() {
        guard let userId = authService.currentUserId else { return }
        isLoading = true
        
        tournamentService.createTournament(
            title: title,
            date: date,
            startTime: formatTime(startTime),
            location: location,
            description: description,
            maxParticipants: maxParticipants,
            organizerId: userId
        ) { success in
            isLoading = false
            if success {
                showSuccess = true
            }
        }
    }
}
