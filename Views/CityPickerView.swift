import SwiftUI

// MARK: - CityPickerView
// Компонент выбора города с поиском
// Используется в регистрации, профиле и создании заявки
struct CityPickerView: View {
    @Binding var selectedCity: String
    @Binding var isPresented: Bool
    
    @State private var searchText = ""
    
    // Фильтрованные города по поисковому запросу
    var filteredCities: [String] {
        CityData.search(searchText)
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Поле ручного ввода (если города нет в списке)
                if !searchText.isEmpty && !filteredCities.contains(searchText) {
                    Button(action: {
                        selectedCity = searchText
                        isPresented = false
                    }) {
                        Label("Указать: \"\(searchText)\"", systemImage: "plus.circle")
                            .foregroundColor(.green)
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
                                    .foregroundColor(.green)
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
                        .foregroundColor(.red)
                }
            }
        }
    }
}
