import SwiftUI

/// Четыре столбика роста: чем сильнее игрок, тем больше закрашено.
/// Уровень читается с одного взгляда, не нужно сравнивать слова. Текст рядом остаётся: цвет не единственный знак.
struct LevelMeter: View {
    let level: String

    var body: some View {
        let filled = LevelMatch.bars(level)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < filled ? AppColor.primary : Color(.systemGray4))
                    .frame(width: 4, height: 6 + CGFloat(index) * 3)
            }
        }
        .accessibilityHidden(true)
    }
}
