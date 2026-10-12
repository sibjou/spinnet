import SwiftUI
import FirebaseFirestore

struct EditTournamentView: View {
    let tournamentId: String
    @ObservedObject var tournamentService: TournamentService
    @Binding var isPresented: Bool
    let onUpdate: () -> Void

    @State private var title = ""
    @State private var date = Date()
    @State private var startTime = Date()
    @State private var endDate = Date()
    @State private var endTime = Date()
    @State private var isMultiDay = false
    @State private var city = ""
    @State private var location = ""
    @State private var description = ""
    @State private var maxParticipants = 16

    @State private var showStartPicker = false
    @State private var showEndPicker = false
    @State private var showCityPicker = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showDeleteConfirm = false

    let participantOptions = [4, 8, 12, 16, 24, 32, 64]

    var minimumDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
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
                        Section("Основная информация") {
                            TextField("Название турнира", text: $title)

                            DatePicker("Дата",
                                       selection: $date,
                                       in: minimumDate...,
                                       displayedComponents: .date)
                                .onChange(of: date) { _, newValue in
                                    if !isMultiDay { endDate = newValue }
                                    if endDate < newValue { endDate = newValue }
                                }

                            HStack {
                                Text("Время начала")
                                Spacer()
                                Button(formatTime(startTime)) { showStartPicker = true }
                                    .foregroundColor(.green)
                            }

                            Toggle("Турнир идёт несколько дней", isOn: $isMultiDay)
                                .tint(.green)
                                .onChange(of: isMultiDay) { _, newValue in
                                    if !newValue { endDate = date }
                                }

                            if isMultiDay {
                                DatePicker("Дата окончания",
                                           selection: $endDate,
                                           in: date...,
                                           displayedComponents: .date)
                            }

                            HStack {
                                Text("Время окончания")
                                Spacer()
                                Button(formatTime(endTime)) { showEndPicker = true }
                                    .foregroundColor(.green)
                            }

                            HStack {
                                Text("Город")
                                Spacer()
                                Button(city.isEmpty ? "Выбрать" : city) {
                                    showCityPicker = true
                                }
                                .foregroundColor(city.isEmpty ? .secondary : .primary)
                            }

                            TextField("Место (клуб, адрес)", text: $location)
                        }

                        Section("Детали") {
                            Picker("Макс. участников", selection: $maxParticipants) {
                                ForEach(participantOptions, id: \.self) { num in
                                    Text("\(num) чел.").tag(num)
                                }
                            }
                        }

                        Section {
                            TextField("Описание...", text: $description)
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
                            Button("Удалить турнир", role: .destructive) {
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
                        .disabled(title.isEmpty || city.isEmpty || location.isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showStartPicker) {
                TimePickerSheet(title: "Время начала", time: $startTime, isPresented: $showStartPicker)
            }
            .sheet(isPresented: $showEndPicker) {
                TimePickerSheet(title: "Время окончания", time: $endTime, isPresented: $showEndPicker)
            }
            .sheet(isPresented: $showCityPicker) {
                CityPickerView(selectedCity: $city, isPresented: $showCityPicker)
            }
            .alert("Удалить турнир?", isPresented: $showDeleteConfirm) {
                Button("Отмена", role: .cancel) {}
                Button("Удалить", role: .destructive) { deleteTournament() }
            } message: {
                Text("Турнир и все записи участников будут удалены")
            }
            .onAppear { loadTournament() }
        }
    }

    private func loadTournament() {
        Firestore.firestore().collection("tournaments").document(tournamentId).getDocument { doc, _ in
            DispatchQueue.main.async {
                if let data = doc?.data() {
                    self.title          = data["title"]          as? String ?? ""
                    self.city           = data["city"]           as? String ?? ""
                    self.location       = data["location"]       as? String ?? ""
                    self.description    = data["description"]    as? String ?? ""
                    self.maxParticipants = data["maxParticipants"] as? Int ?? 16

                    let f = DateFormatter()
                    f.dateFormat = "HH:mm"

                    if let timestamp = data["date"] as? Timestamp {
                        self.date = timestamp.dateValue()
                    }
                    if let timeStr = data["startTime"] as? String {
                        self.startTime = f.date(from: timeStr) ?? Date()
                    }

                    // endDate — если нет, ставим равной date
                    if let endTimestamp = data["endDate"] as? Timestamp {
                        self.endDate = endTimestamp.dateValue()
                        self.isMultiDay = !Calendar.current.isDate(endTimestamp.dateValue(), inSameDayAs: self.date)
                    } else {
                        self.endDate = self.date
                        self.isMultiDay = false
                    }

                    // endTime
                    if let endTimeStr = data["endTime"] as? String {
                        self.endTime = f.date(from: endTimeStr) ?? Date()
                    } else {
                        self.endTime = Calendar.current.date(from: DateComponents(hour: 18, minute: 0)) ?? Date()
                    }
                }
                self.isLoading = false
            }
        }
    }

    private func saveChanges() {
        isSaving = true

        tournamentService.updateTournament(
            tournamentId: tournamentId,
            title: title,
            date: date,
            startTime: formatTime(startTime),
            endDate: isMultiDay ? endDate : date,
            endTime: formatTime(endTime),
            city: city,
            location: location,
            description: description,
            maxParticipants: maxParticipants
        ) { success in
            isSaving = false
            if success {
                onUpdate()
                isPresented = false
            }
        }
    }

    private func deleteTournament() {
        tournamentService.deleteTournament(tournamentId: tournamentId) { success in
            if success {
                onUpdate()
                isPresented = false
            }
        }
    }
}
