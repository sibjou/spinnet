import SwiftUI

// MARK: - CityPickerView
// Компонент выбора города с поиском
// Используется в регистрации, профиле и создании заявки
struct CityPickerView: View {
    @Binding var selectedCity: String
    @Binding var isPresented: Bool
    /// Первая строка «Все города» (для ленты). В регистрации и профиле город обязателен, там строки нет.
    var allCitiesTitle: String? = nil

    @State private var searchText = ""
    
    // Фильтрованные города по поисковому запросу
    var filteredCities: [String] {
        CityData.search(searchText)
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Без фильтра по городу (только пока ничего не ищут)
                if let allCitiesTitle, searchText.isEmpty {
                    Button(action: {
                        selectedCity = allCitiesTitle
                        isPresented = false
                    }) {
                        HStack {
                            Label(allCitiesTitle, systemImage: "globe.europe.africa")
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedCity == allCitiesTitle {
                                Image(systemName: "checkmark")
                                    .foregroundColor(AppColor.primary)
                            }
                        }
                    }
                }

                // Поле ручного ввода (если города нет в списке)
                if !searchText.isEmpty && !filteredCities.contains(searchText) {
                    Button(action: {
                        selectedCity = CityName.canonical(searchText)
                        isPresented = false
                    }) {
                        Label("Указать: \"\(searchText)\"", systemImage: "plus.circle")
                            .foregroundColor(AppColor.primary)
                    }
                }
                
                // Список найденных городов
                ForEach(filteredCities, id: \.self) { city in
                    Button(action: {
                        selectedCity = city
                        isPresented = false
                    }) {
                        HStack {
                            Text(city)
                                .foregroundColor(.primary)
                            Spacer()
                            if city == selectedCity {
                                Image(systemName: "checkmark")
                                    .foregroundColor(AppColor.primary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Поиск города...")
            .navigationTitle("Выбор города")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { isPresented = false }
                }
            }
        }
    }
}
