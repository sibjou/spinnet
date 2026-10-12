import SwiftUI

struct RequestCardView: View {
    let request: SparringRequest
    let isOwnRequest: Bool
    let onTapCard: () -> Void
    let onTapAuthor: () -> Void
    let onBook: () -> Void

    private var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM"
        return f.string(from: request.date)
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Зона 1: Автор (кликабельная отдельно)
            Button(action: onTapAuthor) {
                HStack(spacing: AppSpacing.m) {
                    InitialsAvatar(
                        firstName: request.authorFirstName,
                        lastName:  request.authorLastName,
                        userId:    request.userId,
                        size: AppSize.avatarMedium
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.authorFullName.isEmpty ? "Игрок" : request.authorFullName)
                            .font(.headline)
                            .foregroundColor(AppColor.textPrimary)
                        Text("\(request.authorSkillLevel) · \(request.authorGrip)")
                            .font(.caption)
                            .foregroundColor(AppColor.textSecondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(AppSpacing.l)

            Divider()

            // MARK: - Зона 2: Место и время (кликабельная — детали заявки)
            Button(action: onTapCard) {
                HStack(spacing: AppSpacing.l) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(AppColor.primary)
                                .font(.caption)
                            Text(request.city)
                                .font(.subheadline.bold())
                                .foregroundColor(AppColor.textPrimary)
                        }
                        Text(request.location)
                            .font(.caption)
                            .foregroundColor(AppColor.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                        Text(formattedDate)
                            .font(.subheadline.bold())
                            .foregroundColor(AppColor.textPrimary)
                        Text(request.timeSlot)
                            .font(.caption)
                            .foregroundColor(AppColor.textSecondary)
                    }
                }
                .padding(AppSpacing.l)
                .contentShape(Rectangle()) // вся область — кликабельна
            }
            .buttonStyle(.plain)

            // MARK: - Зона 3: Кнопка
            if !isOwnRequest {
                Button(action: onBook) {
                    Text("Сыграть")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding([.horizontal, .bottom], AppSpacing.l)
            }
        }
        .background(AppColor.cardBackground)
        .cornerRadius(AppRadius.large)
    }
}
