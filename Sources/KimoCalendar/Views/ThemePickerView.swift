import SwiftUI

struct ThemePickerView: View {
    @Binding var style: CalendarStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("主题配色").font(.headline)
            HStack(spacing: 0) {
                ForEach(CalendarStyle.allCases) { option in
                    Button {
                        style = option
                    } label: {
                        VStack(spacing: 7) {
                            swatch(option)
                            Text(option.title)
                                .font(.system(size: 10, weight: style == option ? .semibold : .regular))
                                .foregroundStyle(.primary.opacity(style == option ? 1 : 0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title + "主题")
                    .accessibilityAddTraits(style == option ? .isSelected : [])
                }
            }
        }
    }

    // 展示主题真实底色与选中色，并用选中图标避免只靠颜色区分。
    private func swatch(_ option: CalendarStyle) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 9).fill(option.palette.surface)
            RoundedRectangle(cornerRadius: 5).fill(option.palette.selection)
                .frame(width: 18, height: 20).padding(5)
            if style == option {
                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white).padding(.trailing, 9).padding(.bottom, 11)
            }
        }
        .frame(width: 42, height: 36)
        .overlay(
            RoundedRectangle(cornerRadius: 9).strokeBorder(
                option.palette.selection.opacity(style == option ? 0.9 : 0.12))
        )
        .accessibilityHidden(true)
    }
}
