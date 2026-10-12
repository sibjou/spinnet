import Foundation

// MARK: - CityData
// Список городов для выбора в профиле и заявках
// Сгруппированы по регионам для удобной фильтрации
struct CityData {
    
    // Все доступные города (отсортированы по алфавиту)
    static let allCities: [String] = regions.flatMap { $0.cities }.sorted()
    
    // Регионы с городами
    static let regions: [Region] = [
        Region(name: "Москва и МО", cities: [
            "Москва", "Подольск", "Мытищи", "Балашиха", "Химки",
            "Одинцово", "Красногорск", "Люберцы"
        ]),
        Region(name: "Санкт-Петербург и ЛО", cities: [
            "Санкт-Петербург", "Гатчина", "Выборг", "Петергоф"
        ]),
        Region(name: "Мурманская область", cities: [
            "Мурманск", "Апатиты", "Мончегорск", "Североморск"
        ]),
        Region(name: "Республика Татарстан", cities: [
            "Казань", "Набережные Челны", "Нижнекамск", "Альметьевск"
        ]),
        Region(name: "Новосибирская область", cities: [
            "Новосибирск", "Бердск", "Искитим"
        ]),
        Region(name: "Свердловская область", cities: [
            "Екатеринбург", "Нижний Тагил", "Каменск-Уральский"
        ]),
        Region(name: "Нижегородская область", cities: [
            "Нижний Новгород", "Дзержинск", "Арзамас"
        ]),
        Region(name: "Самарская область", cities: [
            "Самара", "Тольятти", "Сызрань"
        ]),
        Region(name: "Краснодарский край", cities: [
            "Краснодар", "Сочи", "Новороссийск", "Анапа"
        ]),
        Region(name: "Ростовская область", cities: [
            "Ростов-на-Дону", "Таганрог", "Шахты"
        ]),
        Region(name: "Челябинская область", cities: [
            "Челябинск", "Магнитогорск", "Златоуст"
        ]),
        Region(name: "Республика Башкортостан", cities: [
            "Уфа", "Стерлитамак", "Салават"
        ]),
        Region(name: "Воронежская область", cities: [
            "Воронеж", "Борисоглебск"
        ]),
        Region(name: "Красноярский край", cities: [
            "Красноярск", "Норильск", "Ачинск"
        ]),
        Region(name: "Пермский край", cities: [
            "Пермь", "Березники", "Соликамск"
        ]),
        Region(name: "Другой", cities: [
            "Другой город"
        ])
    ]
    
    // Поиск городов по введённому тексту
    static func search(_ query: String) -> [String] {
        if query.isEmpty { return allCities }
        return allCities.filter { $0.lowercased().contains(query.lowercased()) }
    }
    
    // Получить регион по городу
    static func region(for city: String) -> String? {
        return regions.first { $0.cities.contains(city) }?.name
    }
}

// Регион с городами
struct Region: Identifiable {
    let id = UUID()
    let name: String
    let cities: [String]
}
