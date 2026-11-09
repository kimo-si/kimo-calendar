import SwiftUI

enum CalendarTheme {
    static let width: CGFloat = 392
    static let height: CGFloat = 440
    static let corner: CGFloat = 14
    static let contentSpacing: CGFloat = 8
    static let topInset: CGFloat = 12
    static let bottomInset: CGFloat = 6
    static let detailContentHeight: CGFloat = 90
    static let detailInset: CGFloat = 8
    static let dayHeight: CGFloat = 34
    static let dayLabelSpacing: CGFloat = 0
    static let weekSpacing: CGFloat = 2
    static let monthRowsHeight: CGFloat = dayHeight * 6 + weekSpacing * 5
}

struct PanelBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.calendarPalette) private var palette

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                VisualEffectBackground()
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    private var colors: [Color] {
        scheme == .dark
            ? [palette.darkSurface.opacity(0.94), palette.darkSurface.opacity(0.82)]
            : [palette.surface.opacity(0.94), palette.surface.opacity(0.68)]
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    // 使用系统材质，自动响应深浅色与窗口激活状态。
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    // 系统自行更新材质，无需在 SwiftUI 重绘时重复配置。
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct ToolbarButtonStyle: ButtonStyle {
    // 给工具栏提供轻量的按压反馈，避免额外持续动画。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary.opacity(0.78))
            .frame(width: 26, height: 26)
            .background(.primary.opacity(configuration.isPressed ? 0.10 : 0), in: .rect(cornerRadius: 8))
            .contentShape(.rect)
    }
}
