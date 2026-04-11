import SwiftUI

// MARK: - RequestCardView
// Карточка одной заявки в ленте
// Отдельный компонент — так код чище и карточку можно переиспользовать
struct RequestCardView: View {
    let request: [String: Any]    // Данные заявки
    let isOwnRequest: Bool        // Это моя заявка? (чтобы не показывать кнопку "Сыграть" на своей)
    let onBook: () -> Void        // Действие при нажатии "Сыграть" (замыкание/callback)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Верхняя часть: аватар + имя + уровень
            HStack(spacing: 12) {
                // Иконка пользователя
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    // Имя игрока
                    Text(request["userName"] as? String ?? "Загрузка...")
                        .fontWeight(.semibold)
                    
                    // Уровень и хват
                    HStack(spacing: 4) {
                        Text(request["userSkill"] as? String ?? "")
                        Text("•")
                        Text(request["userGrip"] as? String ?? "")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            
            // Место и время
            Label(request["location"] as? String ?? "", systemImage: "mappin.circle.fill")
                .font(.subheadline)
            
            Label(request["timeSlot"] as? String ?? "", systemImage: "clock.fill")
                .font(.subheadline)
            
            // Кого ищет
            Label("Ищет: \(request["desiredLevel"] as? String ?? "")", systemImage: "person.2.fill")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Кнопка "Сыграть" — только если это НЕ моя заявка
            if !isOwnRequest {
                Button(action: onBook) {
                    Text("Сыграть")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
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
