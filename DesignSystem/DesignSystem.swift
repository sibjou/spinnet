import SwiftUI

// MARK: - Цвета
enum AppColor {
    // Стиль как у Instagram и Telegram: интерфейс нейтральный (чёрный/белый/серый),
    // один спокойный синий для кнопок и ссылок, цвет — только у статусов.
    static let primary    = Color(.systemBlue)
    static let ink        = Color(red: 15/255, green: 23/255, blue: 42/255)
    static let success    = Color(.systemGreen)
    static let info       = Color(.systemTeal)
    static let warning    = Color(red: 255/255, green: 149/255, blue: 0/255)   // оранжевый
    static let danger     = Color(red: 255/255, green: 59/255,  blue: 48/255)  // красный
    static let star       = Color(red: 255/255, green: 204/255, blue: 0/255)   // жёлтый

    static let textPrimary   = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    /// Только для значков и украшений: для текста слишком бледный (контраст ниже 3:1). Тексту — textSecondary.
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

/// Кнопка «второго плана» для повторяющихся действий (карточки в ленте): синий текст на светло-синем.
/// Заливка остаётся главной кнопке экрана, иначе десять карточек подряд — десять одинаково громких кнопок.
struct TintedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(AppColor.primary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(AppColor.primary.opacity(configuration.isPressed ? 0.20 : 0.12))
            .cornerRadius(AppRadius.medium)
    }
}
