import SwiftUI

// Используется везде где нужно показать город + место
struct GameLocationLabel: View {
    let city: String
    let location: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.green)
                Text(city.isEmpty ? "Город не указан" : city)
                    .fontWeight(.semibold)
                    .font(.subheadline)
            }
            if !location.isEmpty {
                Text(location)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }
        }
    }
}
