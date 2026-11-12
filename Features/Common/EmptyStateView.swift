import SwiftUI

// MARK: - Пустые экраны
// Пустой экран — это место, где человек решает, что делать дальше: поэтому у него есть картинка,
// короткое объяснение и кнопка. Картинка нарисована кодом (ракетка и мячик), фото для неё не нужны.

/// Ракетка и мячик в круге — знак приложения для пустых экранов и заставок
struct TableTennisMark: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            Circle()
                .fill(AppColor.primary.opacity(0.10))

            // Ракетка: ручка и накладка
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.035)
                    .fill(Color(red: 176 / 255, green: 122 / 255, blue: 74 / 255))
                    .frame(width: size * 0.09, height: size * 0.26)
                    .offset(y: size * 0.27)
                Circle()
                    .fill(AppColor.primary.gradient)
                    .frame(width: size * 0.46, height: size * 0.46)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.35), lineWidth: size * 0.012)
                            .padding(size * 0.03)
                    )
            }
            .rotationEffect(.degrees(-32))
            .offset(x: -size * 0.05, y: -size * 0.03)

            // Мячик
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                .frame(width: size * 0.16, height: size * 0.16)
                .shadow(color: Color.black.opacity(0.12), radius: size * 0.03, y: size * 0.015)
                .offset(x: size * 0.25, y: -size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct EmptyStateView: View {

    enum Art {
        case tableTennis
        case symbol(String)
    }

    let art: Art
    let title: String
    var message: String? = nil
    var primaryTitle: String? = nil
    var primaryAction: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AppSpacing.m) {
            artView
                .padding(.bottom, AppSpacing.xs)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let primaryTitle, let primaryAction {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: 280)
                    .padding(.top, AppSpacing.s)
            }

            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColor.primary)
                    .padding(.vertical, AppSpacing.xs)
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    private var artView: some View {
        switch art {
        case .tableTennis:
            TableTennisMark(size: 104)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 38, weight: .regular))
                .foregroundColor(AppColor.primary)
                .frame(width: 88, height: 88)
                .background(AppColor.primary.opacity(0.10))
                .clipShape(Circle())
                .accessibilityHidden(true)
        }
    }
}
