import SwiftUI

/// Карточка заявки в ленте. Сверху — с кем играть, ниже — когда и где, внизу — одна кнопка.
/// День в карточке не повторяется, если у ленты есть заголовки дней (`showsDay: false`).
struct RequestCardView: View {
    let request: SparringRequest
    var showsDay: Bool = true
    /// Заявка бронируется прямо сейчас: кнопка ждёт ответа и не нажимается повторно
    var isBooking: Bool = false
    let onTapCard: () -> Void
    let onTapAuthor: () -> Void
    let onBook: () -> Void

    private var authorName: String {
        request.authorFullName.isEmpty ? "Игрок" : request.authorFullName
    }

    private var isLive: Bool {
        RequestTiming.isInProgress(day: request.date, slot: request.timeSlot)
    }

    /// Ищет конкретный уровень (а не «Любой»)
    private var wantedLevel: String? {
        LevelMatch.index(request.desiredLevel) == nil ? nil : request.desiredLevel
    }

    var body: some View {
        VStack(spacing: 0) {
            authorRow

            Divider().padding(.horizontal, AppSpacing.l)

            detailsRow

            Button(action: onBook) {
                HStack(spacing: AppSpacing.s) {
                    if isBooking { ProgressView().tint(AppColor.primary) }
                    Text(isBooking ? "Записываем…" : "Сыграть")
                }
            }
            .buttonStyle(TintedButtonStyle())
            .disabled(isBooking)
            .padding([.horizontal, .bottom], AppSpacing.l)
            .accessibilityLabel("Сыграть с игроком \(authorName)")
        }
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }

    // MARK: Автор

    private var authorRow: some View {
        Button(action: onTapAuthor) {
            HStack(spacing: AppSpacing.m) {
                InitialsAvatar(
                    firstName: request.authorFirstName,
                    lastName:  request.authorLastName,
                    userId:    request.userId,
                    size: AppSize.avatarMedium
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(authorName)
                        .font(.headline)
                        .foregroundColor(AppColor.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if LevelMatch.bars(request.authorSkillLevel) > 0 {
                            LevelMeter(level: request.authorSkillLevel)
                        }
                        Text(playerLine)
                            .font(.caption)
                            .foregroundColor(AppColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: AppSpacing.s)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .padding(AppSpacing.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Профиль игрока \(authorName), \(playerLine)")
    }

    /// «Любитель · шейкхолд»; пустые части не показываются
    private var playerLine: String {
        [request.authorSkillLevel, request.authorGrip].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Время и место

    private var detailsRow: some View {
        Button(action: onTapCard) {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                HStack(spacing: AppSpacing.s) {
                    Text(timeText)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(AppColor.textPrimary)
                    if isLive { liveBadge }
                    Spacer(minLength: 0)
                }

                Label {
                    Text(placeText)
                        .font(.subheadline)
                        .foregroundColor(AppColor.textSecondary)
                        .lineLimit(2)
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(AppColor.primary)
                }

                if let wantedLevel {
                    Label {
                        Text("Ищет: \(wantedLevel)")
                            .font(.subheadline)
                            .foregroundColor(AppColor.textSecondary)
                    } icon: {
                        Image(systemName: "scope")
                            .foregroundColor(AppColor.primary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.l)
            .contentShape(Rectangle())   // вся область нажимается: откроются подробности
        }
        .buttonStyle(.plain)
        .accessibilityHint("Открыть подробности заявки")
    }

    /// «18:00 – 20:00» или «Завтра, 18:00 – 20:00», если у ленты нет заголовков дней
    private var timeText: String {
        guard showsDay else { return request.timeSlot }
        let day = RequestTiming.dayWord(for: request.date) ?? AppDate.dayShort(request.date)
        return "\(day), \(request.timeSlot)"
    }

    /// «Томск · Зал ТПУ»; если города нет в заявке — только место
    private var placeText: String {
        [request.city, request.location].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(AppColor.success).frame(width: 6, height: 6)
            Text("Идёт сейчас")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColor.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(AppColor.success.opacity(0.15))
        .clipShape(Capsule())
    }
}
