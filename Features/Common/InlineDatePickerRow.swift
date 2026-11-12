import SwiftUI

// MARK: - InlineDatePickerRow
// Строка «Дата» для форм: показывает выбранный день, по нажатию раскрывает календарь,
// а после выбора дня сама сворачивается (системный компактный календарь не закрывается,
// пока не нажмёшь мимо него — это неудобно).
struct InlineDatePickerRow: View {
    let title: String
    @Binding var date: Date
    /// Раньше этого дня выбрать нельзя (nil — без ограничения)
    var minimumDate: Date? = nil

    @State private var isOpen = false

    private var range: ClosedRange<Date> {
        let calendar = AppLocale.calendar
        let lower = minimumDate ?? calendar.date(byAdding: .year, value: -5, to: Date()) ?? Date()
        let upper = calendar.date(byAdding: .year, value: 5, to: max(lower, Date())) ?? Date()
        return lower...upper
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isOpen.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(AppDate.shortWithWeekday(date))
                        .foregroundColor(isOpen ? AppColor.primary : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                DatePicker("", selection: $date, in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.locale, AppLocale.current)
                    .padding(.top, 8)
                    // Выбрали другой день — календарь убираем. Листание месяцев выбор не меняет.
                    .onChange(of: date) { oldValue, newValue in
                        if !AppLocale.calendar.isDate(oldValue, inSameDayAs: newValue) {
                            withAnimation(.easeInOut(duration: 0.2)) { isOpen = false }
                        }
                    }

                // Если нужный день уже выбран, нажатие на него ничего не меняет — закрываем вручную
                Button("Готово") {
                    withAnimation(.easeInOut(duration: 0.2)) { isOpen = false }
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
            }
        }
    }
}
