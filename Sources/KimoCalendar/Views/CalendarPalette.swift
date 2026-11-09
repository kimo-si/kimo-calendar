import SwiftUI

struct CalendarPalette: Sendable {
    let selection: Color
    let accent: Color
    let surface: Color
    let darkSurface: Color
    let holiday = Self.adaptive(light: 0xCC3447, dark: 0xFF8F9F)
    let solar = Self.adaptive(light: 0x287451, dark: 0x8BCDA9)

    // 每个主题独立定义选中色、阅读强调色及深浅背景，保持深色模式对比度。
    init(style: CalendarStyle) {
        let colors: (selection: UInt32, darkAccent: UInt32, surface: UInt32, darkSurface: UInt32) =
            switch style {
            case .lavender: (0x4356DF, 0xADB8FF, 0xEDEBFA, 0x242334)
            case .ocean: (0x1768BF, 0x91C8FF, 0xE6F0FA, 0x1C2A38)
            case .forest: (0x25745A, 0x8ED5B8, 0xE8F1EB, 0x202E28)
            case .sakura: (0xB63F72, 0xFFACCE, 0xFAEAF1, 0x342430)
            case .apricot: (0xA45A1D, 0xFFC98D, 0xFAF0E3, 0x342B23)
            case .graphite: (0x4B596D, 0xBCCADB, 0xEDF0F3, 0x242A32)
            }
        selection = Self.color(colors.selection)
        accent = Self.adaptive(light: colors.selection, dark: colors.darkAccent)
        surface = Self.color(colors.surface)
        darkSurface = Self.color(colors.darkSurface)
    }

    // 将主题颜色交给系统外观解析，避免深浅色切换时重新创建视图。
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                return nsColor(value)
            })
    }

    // 从主题常量生成 SwiftUI 色彩。
    private static func color(_ value: UInt32) -> Color { Color(nsColor: nsColor(value)) }

    // 统一十六进制配色解码，不在视图中散落 RGB 魔法数字。
    private static func nsColor(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
    }
}

private struct CalendarPaletteKey: EnvironmentKey {
    static let defaultValue = CalendarPalette(style: .lavender)
}

extension EnvironmentValues {
    var calendarPalette: CalendarPalette {
        get { self[CalendarPaletteKey.self] }
        set { self[CalendarPaletteKey.self] = newValue }
    }
}
