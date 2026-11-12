import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct CreateRequestView: View {
    @ObservedObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    // По умолчанию — сегодня, начало через час; поздним вечером — завтра (см. MeetingDefaults)
    @State private var date: Date
    @State private var location = ""
    @State private var city = ""
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var desiredLevel = "Любой"
    @State private var showSuccess = false
    @State private var isLoading = false
    @State private var showStartPicker = false
    @State private var showEndPicker = false

    /// «Любой» первым: это значение по умолчанию
    let levels = ["Любой", "Начинающий", "Любитель", "Продвинутый", "Профессионал"]

    /// Места, где человек уже играл: подставляются одним касанием
    @State private var recentVenues: [String] = []

    init(authService: AuthService) {
        self.authService = authService
        let slot = MeetingDefaults.initialSlot()
        _date = State(initialValue: slot.day)
        _startTime = State(initialValue: slot.start)
        _endTime = State(initialValue: slot.end)
    }

    var minimumDate: Date { Calendar.current.startOfDay(for: Date()) }

    private var startsInPast: Bool {
        MeetingDefaults.startsInPast(day: date, start: startTime)
    }

    private func formatTime(_ date: Date) -> String { AppDate.clock(date) }

    private var canPublish: Bool {
        !location.trimmingCharacters(in: .whitespaces).isEmpty
            && !city.isEmpty
            && !isLoading
            && endTime > startTime
            && !startsInPast
    }

    private func loadRecentVenues() {
        guard let userId = authService.currentUserId else { return }
        recentVenues = UserDefaults.standard.stringArray(forKey: RecentVenues.storageKey(userId: userId)) ?? []
    }

    private func rememberVenue(_ venue: String, userId: String) {
        let updated = RecentVenues.updated(recentVenues, adding: venue)
        recentVenues = updated
        UserDefaults.standard.set(updated, forKey: RecentVenues.storageKey(userId: userId))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Когда") {
                    InlineDatePickerRow(title: "Дата", date: $date, minimumDate: minimumDate)

                    HStack {
                        Text("Начало")
                        Spacer()
                        Button(formatTime(startTime)) { showStartPicker = true }
                            .foregroundColor(AppColor.primary)
                    }
                    HStack {
                        Text("Конец")
                        Spacer()
                        Button(formatTime(endTime)) { showEndPicker = true }
                            .foregroundColor(AppColor.primary)
                    }
                }

                Section {
                    // Город — отдельное поле: по нему заявку находят в ленте
                    CityRow(city: $city)

                    TextField("Место (клуб, адрес)", text: $location)

                    // Недавние места: нажал — подставилось
                    let suggestions = RecentVenues.suggestions(recentVenues, typed: location)
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.s) {
                                ForEach(suggestions, id: \.self) { venue in
                                    Button { location = venue } label: {
                                        Label(venue, systemImage: "clock.arrow.circlepath")
                                            .font(.subheadline)
                                            .lineLimit(1)
                                            .foregroundColor(AppColor.primary)
                                            .padding(.horizontal, 12)
                                            .frame(minHeight: 34)
                                            .background(AppColor.primary.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Где")
                } footer: {
                    if city.isEmpty {
                        Text("Выберите город: по нему заявку найдут в ленте")
                    } else if location.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Напишите, где будете играть — клуб или адрес")
                    }
                }

                Section("Кого ищете") {
                    Picker("Желаемый уровень партнёра", selection: $desiredLevel) {
                        ForEach(levels, id: \.self) { Text($0) }
                    }
                }

                if endTime <= startTime {
                    Section {
                        Label("Время конца должно быть позже начала", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColor.danger)
                            .font(.footnote)
                    }
                } else if startsInPast {
                    Section {
                        Label("Это время уже прошло — выберите другое", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColor.danger)
                            .font(.footnote)
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
                    .disabled(!canPublish)
                    .foregroundColor(.white)
                    .listRowBackground(canPublish ? AppColor.primary : Color(.systemGray3))
                }
            }
            .connectionNotice()
            .navigationTitle("Новая заявка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .sheet(isPresented: $showStartPicker) {
                TimePickerSheet(title: "Начало", time: $startTime, isPresented: $showStartPicker)
            }
            .sheet(isPresented: $showEndPicker) {
                TimePickerSheet(title: "Конец", time: $endTime, isPresented: $showEndPicker)
            }
            .alert("Заявка опубликована!", isPresented: $showSuccess) {
                Button("OK") {
                    location = ""
                    dismiss()
                }
            } message: {
                Text("Игроки города «\(CityName.canonical(city))» увидят её в ленте. Изменить или отменить заявку можно в профиле, во вкладке «Игры».")
            }
            .onAppear {
                // Подставляем город из профиля по умолчанию
                if city.isEmpty, let profileCity = authService.userProfile?.city {
                    city = CityName.canonical(profileCity)
                }
                loadRecentVenues()
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
            "city":             CityName.canonical(city),
            "location":         location.trimmingCharacters(in: .whitespaces),
            "desiredLevel":     desiredLevel,
            "status":           "active",
            "createdAt":        Timestamp()
        ]

        SparringService().createRequest(data: data) { success in
            isLoading = false
            if success {
                rememberVenue(location, userId: userId)
                showSuccess = true
            }
        }
    }
}
