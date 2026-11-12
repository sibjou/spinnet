import SwiftUI
import MapKit
import UIKit

// MARK: - Мелкие части экранов переписки

/// Аватар с зелёной точкой, если человек сейчас в сети
struct OnlineAvatar: View {
    let fullName: String
    let userId: String
    var size: CGFloat = 52
    var isOnline: Bool = false

    var body: some View {
        InitialsAvatar(fullName: fullName, userId: userId, size: size)
            .overlay(alignment: .bottomTrailing) {
                if isOnline {
                    Circle()
                        .fill(AppColor.success)
                        .frame(width: size * 0.27, height: size * 0.27)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .offset(x: 1, y: 1)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// Галочки: одна — отправлено, две — партнёр прочитал
struct ReadTicks: View {
    let isRead: Bool
    var sentColor: Color = Color.secondary
    var readColor: Color = AppColor.primary

    var body: some View {
        HStack(spacing: -5) {
            Image(systemName: "checkmark")
            if isRead {
                Image(systemName: "checkmark")
            }
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(isRead ? readColor : sentColor)
        .accessibilityLabel(isRead ? "Прочитано" : "Отправлено")
    }
}

/// Кружок с числом непрочитанных
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 20, minHeight: 20)
            .background(AppColor.primary)
            .clipShape(Capsule())
            .accessibilityLabel("Непрочитанных: \(count)")
    }
}

/// «в сети» / «был(а) сегодня в 14:05»; сама обновляется раз в полминуты
struct PresenceText: View {
    let info: PresenceInfo

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let text = info.statusText(now: context.date) {
                Text(text)
                    .font(.caption)
                    .foregroundColor(info.showsOnlineDot(now: context.date) ? AppColor.primary : Color.secondary)
            }
        }
    }
}

/// Заголовок дня внутри переписки
struct DaySeparatorView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }
}

// MARK: - Открыть Apple Карты
enum MapsOpener {
    static func open(name: String, city: String, latitude: Double?, longitude: Double?) {
        guard let url = MapsLink.url(name: name, city: city, latitude: latitude, longitude: longitude) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Карточка встречи вверху диалога
struct MeetingSummaryCard: View {
    let dateText: String
    let slot: String
    let city: String
    let location: String
    let onOpenMap: () -> Void

    private var placeText: String {
        [city, location]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(dateText), \(slot)", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !placeText.isEmpty {
                    Label(placeText, systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Button(action: onOpenMap) {
                Image(systemName: "map.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppColor.primary)
                    .frame(width: 38, height: 38)
                    .background(AppColor.primary.opacity(0.12))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Открыть в Картах")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Маленькая карта с меткой (для предложенного места)
struct PlaceMapPreview: View {
    let latitude: Double
    let longitude: Double
    let title: String
    let onTap: () -> Void

    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
        )

        Map(initialPosition: .region(region), interactionModes: []) {
            Marker(title, coordinate: coordinate)
        }
        .allowsHitTesting(false)
        .frame(maxWidth: 240)
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(Color.clear.contentShape(Rectangle()).onTapGesture(perform: onTap))
        .accessibilityLabel("Карта: \(title)")
    }
}
