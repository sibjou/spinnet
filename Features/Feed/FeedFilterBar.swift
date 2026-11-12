import SwiftUI

/// Быстрые фильтры над лентой: город, день, «Подходит мне».
/// Город показан всегда: человек видит, чьи заявки перед ним, и меняет город в одно касание.
/// Повторное касание включённого фильтра выключает его.
struct FeedFilterBar: View {
    let city: String
    @Binding var day: FeedDay
    @Binding var onlyMyLevel: Bool
    /// Свой уровень известен: без него «Подходит мне» нечего сравнивать
    let canFilterByLevel: Bool
    let onCityTap: () -> Void

    private static let quickDays: [FeedDay] = [.today, .tomorrow, .weekend]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.s) {
                cityChip

                ForEach(Self.quickDays, id: \.self) { option in
                    chip(option.title, isOn: day == option) {
                        day = (day == option) ? .any : option
                    }
                }

                if canFilterByLevel {
                    chip("Подходит мне", systemImage: "scope", isOn: onlyMyLevel) {
                        onlyMyLevel.toggle()
                    }
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.vertical, AppSpacing.s)
        }
    }

    // MARK: Город

    private var cityChip: some View {
        Button(action: onCityTap) {
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                Text(city).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(AppColor.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(AppColor.primary.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Город: \(city)")
        .accessibilityHint("Выбрать другой город")
    }

    // MARK: Переключатель

    private func chip(_ title: String,
                      systemImage: String? = nil,
                      isOn: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(isOn ? .semibold : .regular))
            .foregroundColor(isOn ? .white : AppColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(isOn ? AppColor.primary : Color(.systemGray6))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
