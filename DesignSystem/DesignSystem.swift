import SwiftUI

// MARK: - Цвета
enum AppColor {
    static let primary    = Color(red: 52/255,  green: 199/255, blue: 89/255)  // зелёный
    static let info       = Color(red: 0/255,   green: 122/255, blue: 255/255) // синий
    static let warning    = Color(red: 255/255, green: 149/255, blue: 0/255)   // оранжевый
    static let danger     = Color(red: 255/255, green: 59/255,  blue: 48/255)  // красный
    static let star       = Color(red: 255/255, green: 204/255, blue: 0/255)   // жёлтый

    static let textPrimary   = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary  = Color(.tertiaryLabel)

    static let background        = Color(.systemBackground)
    static let backgroundSecondary = Color(.secondarySystemBackground)
    static let cardBackground    = Color(.systemGray6)
    static let separator         = Color(.separator)
}

// MARK: - Отступы (8pt grid)
enum AppSpacing {
    static let xs:  CGFloat = 4
    static let s:   CGFloat = 8
    static let m:   CGFloat = 12
    static let l:   CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Радиусы скругления
enum AppRadius {
    static let small:  CGFloat = 8
    static let medium: CGFloat = 12
    static let large:  CGFloat = 16
}

// MARK: - Размеры
enum AppSize {
    static let buttonHeight:   CGFloat = 50
    static let iconSmall:      CGFloat = 16
    static let iconMedium:     CGFloat = 24
    static let iconLarge:      CGFloat = 44
    static let avatarSmall:    CGFloat = 32
    static let avatarMedium:   CGFloat = 44
    static let avatarLarge:    CGFloat = 80
}

// MARK: - Стандартные стили кнопок

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: AppSize.buttonHeight)
            .background(AppColor.primary)
            .cornerRadius(AppRadius.medium)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(AppColor.primary)
            .frame(maxWidth: .infinity)
            .frame(height: AppSize.buttonHeight)
            .background(AppColor.primary.opacity(0.1))
            .cornerRadius(AppRadius.medium)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
