import SwiftUI

/// Строка формы «Город»: показывает выбранный город и открывает список с поиском.
/// Город выбирается из списка, а не печатается: так «Томск» и «томск » не превращаются в два разных города.
struct CityRow: View {
    @Binding var city: String
    var title: String = "Город"

    @State private var showPicker = false

    var body: some View {
        Button { showPicker = true } label: {
            HStack {
                Text(title)
                    .foregroundColor(AppColor.textPrimary)
                Spacer()
                Text(city.isEmpty ? "Выбрать" : city)
                    .foregroundColor(city.isEmpty ? AppColor.primary : AppColor.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(title): \(city.isEmpty ? "не выбран" : city)")
        .sheet(isPresented: $showPicker) {
            CityPickerView(selectedCity: $city, isPresented: $showPicker)
        }
    }
}
