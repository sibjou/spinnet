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

    // Пустое состояние: значок, объяснение и, если есть куда пойти, кнопка
    func emptyState(icon: String,
                    title: String,
                    subtitle: String,
                    actionTitle: String? = nil,
                    action: (() -> Void)? = nil) -> some View {
        EmptyStateView(
            art: .symbol(icon),
            title: title,
            message: subtitle,
            primaryTitle: actionTitle,
            primaryAction: action
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
    }

    // MARK: - Бейдж статуса игры

    // Цвет — точка, слова — обычным чёрным: читается на любом фоне, и статус понятен без цвета
    func statusBadge(_ status: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 7, height: 7)
            Text(statusText(status))
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColor.textPrimary)
        }
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

    // Цвет статуса по смыслу: синий=ждёт игрока, бирюзовый=игра назначена, оранжевый=идёт, серый=закончено.
    // Красного нет: истёкшая заявка — не ошибка
    func statusColor(_ status: String) -> Color {
        switch status {
        case "active":      return AppColor.primary
        case "booked":      return AppColor.info
        case "in_progress": return AppColor.warning
        case "completed":   return AppColor.textSecondary
        case "expired":     return AppColor.textSecondary
        default:            return AppColor.textSecondary
        }
    }
}
