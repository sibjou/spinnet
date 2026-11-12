import SwiftUI

// MARK: - Предложить другое время
// День из календаря, начало и конец — часы и минуты, быстрые варианты длительности.
// Проверки (конец позже начала, не в прошлом, не то же самое) — в TimeProposal.
struct ProposeTimeSheet: View {
    let currentDay: Date
    let currentSlot: String
    /// День (начало суток), строка времени «19:00 – 21:00» и признак, что день изменился
    let onSend: (_ day: Date, _ slot: String, _ isNewDay: Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var day: Date
    @State private var startMinutes: Int
    @State private var endMinutes: Int

    private static let durations = [60, 90, 120, 180]

    init(currentDay: Date, currentSlot: String, onSend: @escaping (Date, String, Bool) -> Void) {
        self.currentDay = currentDay
        self.currentSlot = currentSlot
        self.onSend = onSend

        let today = Calendar.current.startOfDay(for: Date())
        let initialDay = max(Calendar.current.startOfDay(for: currentDay), today)
        let range = GameSlot.minutes(from: currentSlot)

        _day = State(initialValue: initialDay)
        _startMinutes = State(initialValue: range?.start ?? 18 * 60)
        _endMinutes = State(initialValue: min(range?.end ?? 20 * 60, 24 * 60 - 1))
    }

    private var proposal: TimeProposal {
        TimeProposal(day: day, startMinutes: startMinutes, endMinutes: endMinutes)
    }

    private var problem: TimeProposal.Problem? {
        proposal.problem(currentDay: currentDay, currentSlot: currentSlot)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("День") {
                    DatePicker(
                        "Дата",
                        selection: $day,
                        in: Calendar.current.startOfDay(for: Date())...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                }

                Section("Время") {
                    DatePicker("Начало", selection: clockBinding($startMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("Конец", selection: clockBinding($endMinutes), displayedComponents: .hourAndMinute)

                    HStack(spacing: 8) {
                        ForEach(Self.durations, id: \.self) { minutes in
                            durationButton(minutes)
                        }
                    }
                }

                Section {
                    if let problem {
                        Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColor.danger)
                    } else {
                        Label(
                            "\(proposal.summary()) · \(TimeProposal.durationText(proposal.durationMinutes))",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundColor(AppColor.success)
                    }
                } header: {
                    Text("Что получится")
                } footer: {
                    Text("Партнёр получит предложение и сможет принять или отклонить его. Время встречи изменится, только если он согласится.")
                }
            }
            .navigationTitle("Другое время")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Предложить") { send() }
                        .disabled(problem != nil)
                }
            }
            // Сдвинули начало — конец едет следом, длительность остаётся
            .onChange(of: startMinutes) { oldValue, newValue in
                let length = max(endMinutes - oldValue, TimeProposal.minDuration)
                endMinutes = min(newValue + length, 24 * 60 - 1)
            }
        }
    }

    private func durationButton(_ minutes: Int) -> some View {
        let isSelected = endMinutes - startMinutes == minutes
        return Button {
            endMinutes = min(startMinutes + minutes, 24 * 60 - 1)
        } label: {
            Text(TimeProposal.durationText(minutes))
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? AppColor.primary : Color(.systemGray5))
                .foregroundColor(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.borderless)
    }

    private func send() {
        guard problem == nil else { return }
        let isNewDay = !Calendar.current.isDate(day, inSameDayAs: currentDay)
        onSend(Calendar.current.startOfDay(for: day), proposal.slot, isNewDay)
        dismiss()
    }

    /// Минуты от полуночи ↔ дата для DatePicker (важны только часы и минуты)
    private func clockBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                Calendar.current.date(
                    bySettingHour: minutes.wrappedValue / 60,
                    minute: minutes.wrappedValue % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
