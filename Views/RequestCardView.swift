import SwiftUI
import FirebaseFirestore

// MARK: - RequestCardView
// Карточка одной заявки в ленте
struct RequestCardView: View {
    let request: [String: Any]    // Данные заявки
    let isOwnRequest: Bool        // Это моя заявка? (чтобы не показывать кнопку "Сыграть" на своей)
    let onBook: () -> Void        // Действие при нажатии "Сыграть" (замыкание/callback)
    
    // Форматирование даты из Firestore Timestamp в читаемый вид
    var formattedDate: String {
        guard let timestamp = request["date"] as? Timestamp else { return "Дата не указана" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")  // Русский формат даты
        formatter.dateFormat = "d MMMM yyyy"             // Пример: "15 апреля 2026"
        return formatter.string(from: timestamp.dateValue())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    // Имя кликабельное — переход к профилю игрока
                    if let userId = request["userId"] as? String {
                        NavigationLink {
                            PlayerProfileView(userId: userId)
                        } label: {
                            Text(request["userName"] as? String ?? "Загрузка...")
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }
                    } else {
                        Text(request["userName"] as? String ?? "Загрузка...")
                            .fontWeight(.semibold)
                    }
                    
                    HStack(spacing: 4) {
                        Text(request["userSkill"] as? String ?? "")
                        Text("•")
                        Text(request["userGrip"] as? String ?? "")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            
            // Место
            Label(request["location"] as? String ?? "", systemImage: "mappin.circle.fill")
                .font(.subheadline)
            
            // Дата — теперь отображается
            Label(formattedDate, systemImage: "calendar")
                .font(.subheadline)
            
            // Время
            Label(request["timeSlot"] as? String ?? "", systemImage: "clock.fill")
                .font(.subheadline)
            
            // Кого ищет
            Label("Ищет: \(request["desiredLevel"] as? String ?? "")", systemImage: "person.2.fill")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Кнопка "Сыграть" — только чужие заявки
            if !isOwnRequest {
                Button(action: onBook) {
                    Text("Сыграть")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .contentShape(Rectangle()) // Вся область кнопки кликабельна
            } else {
                // Если моя заявка — показываем пометку
                Text("Ваша заявка")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 6)
    }
}
