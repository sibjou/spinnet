import SwiftUI

/// Аватар с инициалами — пока нет загрузки фото.
/// Цвет стабилен для каждого пользователя (зависит от userId).
struct InitialsAvatar: View {
    let firstName: String
    let lastName: String
    let userId: String
    var size: CGFloat = AppSize.avatarMedium

    private static let palette: [Color] = [
        Color(red: 30/255,  green: 58/255,  blue: 95/255),   // тёмно-синий
        Color(red: 71/255,  green: 85/255,  blue: 105/255),  // сланец
        Color(red: 15/255,  green: 118/255, blue: 110/255),  // морская волна
        Color(red: 107/255, green: 63/255,  blue: 160/255),  // сливовый
        Color(red: 180/255, green: 68/255,  blue: 42/255),   // кирпичный
        Color(red: 91/255,  green: 107/255, blue: 47/255)    // оливковый
    ]

    private var initials: String {
        let f = firstName.first.map { String($0) } ?? ""
        let l = lastName.first.map { String($0) } ?? ""
        let result = (f + l).uppercased()
        return result.isEmpty ? "?" : result
    }

    private var color: Color {
        // String.hashValue меняется между запусками, поэтому считаем сумму вручную
        let sum = userId.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Self.palette[abs(sum) % Self.palette.count]
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(color.gradient)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

extension InitialsAvatar {
    /// Для мест, где известно только полное имя («Имя Фамилия»)
    init(fullName: String, userId: String, size: CGFloat = AppSize.avatarMedium) {
        let parts = fullName.split(separator: " ", omittingEmptySubsequences: true)
        self.init(
            firstName: parts.first.map(String.init) ?? "",
            lastName:  parts.dropFirst().first.map(String.init) ?? "",
            userId: userId,
            size: size
        )
    }
}
