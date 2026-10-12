import SwiftUI
import FirebaseFirestore

struct RequestDetailView: View {
    let request: SparringRequest
    @ObservedObject var authService: AuthService
    let onBook: () -> Void

    @Environment(\.dismiss) var dismiss

    private var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM yyyy, EEEE"
        return f.string(from: request.date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.l) {

                    // MARK: - Автор (кликабельный)
                    NavigationLink {
                        PlayerProfileView(userId: request.userId)
                    } label: {
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
                                Text("\(request.authorSkillLevel) · \(request.authorGrip) · \(request.authorPlayStyle)")
                                    .font(.subheadline)
                                    .foregroundColor(AppColor.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(AppColor.textTertiary)
                                .font(.caption)
                        }
                        .padding(AppSpacing.l)
                        .background(AppColor.cardBackground)
                        .cornerRadius(AppRadius.medium)
                    }
                    .buttonStyle(.plain)

                    // MARK: - Информация о встрече
                    VStack(alignment: .leading, spacing: AppSpacing.m) {
                        infoRow(icon: "mappin.circle.fill", title: "Город", value: request.city)
                        infoRow(icon: "mappin", title: "Место", value: request.location)
                        infoRow(icon: "calendar", title: "Дата", value: formattedDate)
                        infoRow(icon: "clock.fill", title: "Время", value: request.timeSlot)
                        infoRow(icon: "person.2.fill", title: "Ищет", value: request.desiredLevel)
                    }
                    .padding(AppSpacing.l)
                    .background(AppColor.cardBackground)
                    .cornerRadius(AppRadius.medium)

                    // MARK: - Кнопка карты
                    Button {
                        let query = "\(request.city) \(request.location)"
                            .trimmingCharacters(in: .whitespaces)
                        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "maps://?q=\(encoded)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "map.fill")
                            Text("Открыть в картах")
                                .font(.headline)
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    // MARK: - Кнопка "Сыграть"
                    Button {
                        onBook()
                        dismiss()
                    } label: {
                        Text("Сыграть")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Spacer(minLength: AppSpacing.xl)
                }
                .padding(AppSpacing.l)
            }
            .navigationTitle("Заявка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: AppSpacing.m) {
            Image(systemName: icon)
                .foregroundColor(AppColor.primary)
                .frame(width: AppSize.iconMedium)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(AppColor.textSecondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(AppColor.textPrimary)
            }
            Spacer()
        }
    }
}
