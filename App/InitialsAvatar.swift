import SwiftUI

/// Аватар с инициалами — пока нет загрузки фото.
/// Цвет стабилен для каждого пользователя (зависит от userId).
struct InitialsAvatar: View {
    let firstName: String
    let lastName: String
    let userId: String
    var size: CGFloat = AppSize.avatarMedium

    private static let palette: [Color] = [
        .green, .blue, .orange, .purple, .pink, .teal, .indigo, .red
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
