import SwiftUI
import FirebaseFirestore

// MARK: - ProfileView: общие компоненты

extension ProfileView {
    // MARK: - Универсальные компоненты

    // Заголовок секции — кликабельный, со стрелкой и счётчиком
    func sectionHeader(_ title: String, count: Int, key: String) -> some View {
        Button {
            toggleSection(key)
        } label: {
            HStack(spacing: AppSpacing.s) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColor.textPrimary)

                // Счётчик элементов в секции
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundColor(AppColor.textSecondary)
                    .padding(.horizontal, AppSpacing.s)
                    .padding(.vertical, 2)
                    .background(AppColor.cardBackground)
                    .cornerRadius(AppRadius.small)

                Spacer()

                // Стрелка: вниз = развёрнуто, влево = свёрнуто
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                    .foregroundColor(AppColor.textSecondary)
                    .rotationEffect(.degrees(isCollapsed(key) ? -90 : 0))
            }
        }
        .buttonStyle(.plain)
    }

    // Пустое состояние с иконкой и поясняющим текстом
    func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: AppSpacing.m) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(AppColor.textTertiary)
            Text(title)
                .font(.headline)
                .foregroundColor(AppColor.textSecondary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(AppColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
    }

    // MARK: - Бейдж статуса игры

    func statusBadge(_ status: String) -> some View {
        Text(statusText(status))
            .font(.caption.bold())
            .foregroundColor(statusColor(status))
            .padding(.horizontal, AppSpacing.s)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.12))
            .cornerRadius(AppRadius.small)
    }

    // Перевод статуса на русский
    func statusText(_ status: String) -> String {
        switch status {
        case "active":      return "Активна"
        case "booked":      return "Забронирована"
        case "in_progress": return "Идёт"
        case "completed":   return "Завершена"
        case "expired":     return "Истекла"
        default:            return status
        }
    }

    // Цвет статуса по смыслу: зелёный=активная, синий=инфо, оранжевый=внимание, красный=ошибка
    func statusColor(_ status: String) -> Color {
        switch status {
        case "active":      return AppColor.primary
        case "booked":      return AppColor.info
        case "in_progress": return AppColor.warning
        case "completed":   return AppColor.textSecondary
        case "expired":     return AppColor.danger
        default:            return AppColor.textSecondary
        }
    }
}
