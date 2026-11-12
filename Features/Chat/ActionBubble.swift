import SwiftUI

// MARK: - Пузырь события в диалоге
// Обычное сообщение, быстрый статус («опаздываю», «на месте») или предложение
// (подтвердить, время, место, отмена) с кнопками «Принять» и «Отклонить» у получателя.
struct ActionBubble: View {
    let action: MeetingAction
    let isMine: Bool
    /// Партнёр уже открывал диалог после этого сообщения (только для моих)
    let isRead: Bool
    let city: String
    /// Предложение партнёра ждёт моего ответа
    let canRespond: Bool
    let isBusy: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    // MARK: Цвета

    private var textColor: Color { isMine ? Color.white : Color.primary }
    private var secondaryColor: Color { isMine ? Color.white.opacity(0.8) : Color.secondary }
    private var fillColor: Color { isMine ? AppColor.primary : Color(.systemGray5) }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: isMine ? 18 : 5,
            bottomTrailingRadius: isMine ? 5 : 18,
            topTrailingRadius: 18
        )
    }

    // MARK: Вид

    var body: some View {
        HStack(spacing: 0) {
            if isMine { Spacer(minLength: 56) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 6) {
                    content
                    footer
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(fillColor, in: bubbleShape)

                if canRespond {
                    responseButtons
                }
            }

            if !isMine { Spacer(minLength: 56) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch action.type {
        case .message:
            Text(action.proposedValue)
                .foregroundColor(textColor)
        case .late:
            Label("Опаздываю на \(action.proposedValue) мин", systemImage: "clock.badge.exclamationmark")
                .foregroundColor(textColor)
        case .arrived:
            Label("Я на месте", systemImage: "mappin.circle.fill")
                .foregroundColor(textColor)
        case .confirm:
            proposal(icon: "checkmark.seal.fill", title: "Подтверждаю встречу", detail: "Время и место подходят")
        case .suggestTime:
            proposal(icon: "clock.arrow.2.circlepath", title: "Предлагаю другое время", detail: action.timeText())
        case .cancelRequest:
            proposal(icon: "xmark.circle", title: "Предлагаю отменить встречу", detail: "Если вы согласитесь, встреча будет отменена")
        case .suggestLocation:
            placeProposal
        }
    }

    private func proposal(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(textColor)
            if !detail.isEmpty {
                Text(detail)
                    .font(.body.weight(.medium))
                    .foregroundColor(textColor)
            }
        }
    }

    private var placeProposal: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Предлагаю место", systemImage: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(textColor)

            Text(action.proposedValue)
                .font(.body.weight(.medium))
                .foregroundColor(textColor)

            if !action.note.isEmpty {
                Text(action.note)
                    .font(.footnote)
                    .foregroundColor(secondaryColor)
            }

            if let latitude = action.latitude, let longitude = action.longitude {
                PlaceMapPreview(latitude: latitude, longitude: longitude, title: action.proposedValue) {
                    MapsOpener.open(name: action.proposedValue, city: city, latitude: latitude, longitude: longitude)
                }
                Text("Нажмите на карту, чтобы открыть в Картах")
                    .font(.caption2)
                    .foregroundColor(secondaryColor)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if action.type.needsResponse {
                statusLabel
            }
            Spacer(minLength: 0)
            Text(ChatTime.clock(action.createdAt))
                .font(.caption2)
                .foregroundColor(secondaryColor)
            if isMine {
                ReadTicks(isRead: isRead, sentColor: Color.white.opacity(0.7), readColor: Color.white)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch action.status {
        case .pending:
            Label("Ждёт ответа", systemImage: "clock")
                .font(.caption2.weight(.semibold))
                .foregroundColor(secondaryColor)
        case .accepted:
            Label("Принято", systemImage: "checkmark.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundColor(isMine ? Color.white : AppColor.success)
        case .declined:
            Label("Отклонено", systemImage: "xmark.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundColor(isMine ? Color.white : AppColor.danger)
        case .info:
            EmptyView()
        }
    }

    private var responseButtons: some View {
        HStack(spacing: 8) {
            Button(action: onAccept) {
                Text("Принять")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(AppColor.primary)
                    .foregroundColor(Color.white)
                    .clipShape(Capsule())
            }
            Button(action: onDecline) {
                Text("Отклонить")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .foregroundColor(AppColor.danger)
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
    }
}
