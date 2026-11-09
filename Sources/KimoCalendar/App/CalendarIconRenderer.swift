import AppKit

enum CalendarIconRenderer {
    enum Style { case menuBar, application }

    static let menuBarSize = NSSize(width: 21, height: 18)
    private static let menuBarFontSize: CGFloat = 13
    private static let menuBarBorderWidth: CGFloat = 1.15
    private static let menuBarCorner: CGFloat = 3.5
    private static let canvasSize = 1024.0
    private static let monthNames = [
        "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
    ]
    private static let paper = NSRect(x: 48, y: 48, width: 928, height: 928)
    private static let heading = NSRect(x: 48, y: 676, width: 928, height: 300)
    private static let dayArea = NSRect(x: 48, y: 64, width: 928, height: 620)

    // 菜单栏使用单色模板以适配系统明暗背景，应用包保留红白日历。
    static func image(for date: Date, size: NSSize, style: Style) -> NSImage {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let components = calendar.dateComponents([.month, .day], from: date)
        let month = monthNames[(components.month ?? 1) - 1]
        let day = String(components.day ?? 1)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            if style == .menuBar {
                drawMenuBar(day: day, in: rect)
            } else {
                context.scaleBy(x: rect.width / canvasSize, y: rect.height / canvasSize)
                drawPaper()
                drawText(month, size: 166, color: .white, in: heading)
                drawText(day, size: day.count == 1 ? 590 : 555, color: NSColor(white: 0.14, alpha: 1), in: dayArea)
            }
            context.restoreGState()
            return true
        }
        image.isTemplate = style == .menuBar
        return image
    }

    // 在较矮的圆角边框中居中绘制等宽日号，月份不占用菜单栏高度。
    private static func drawMenuBar(day: String, in rect: NSRect) {
        let inset = menuBarBorderWidth / 2 + 0.25
        let outline = NSBezierPath(
            roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: menuBarCorner, yRadius: menuBarCorner)
        outline.lineWidth = menuBarBorderWidth
        NSColor.black.setStroke()
        outline.stroke()
        let text = NSAttributedString(
            string: day,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: menuBarFontSize, weight: .medium),
                .foregroundColor: NSColor.black,
            ])
        let size = text.size()
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    // 在圆角纸张内绘制红色月份栏，全部由原生矢量合成，无需载入图片。
    private static func drawPaper() {
        NSGraphicsContext.saveGraphicsState()
        let outline = NSBezierPath(roundedRect: paper, xRadius: 220, yRadius: 220)
        outline.addClip()
        NSGradient(starting: NSColor(white: 0.89, alpha: 1), ending: .white)?.draw(in: paper, angle: 90)
        let top = NSColor(srgbRed: 1, green: 0.47, blue: 0.42, alpha: 1)
        let bottom = NSColor(srgbRed: 0.89, green: 0.23, blue: 0.19, alpha: 1)
        NSGradient(starting: bottom, ending: top)?.draw(in: heading, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
    }

    // 根据字体实际尺寸居中排版，保证单日号和双日号都落在纸张内。
    private static func drawText(_ value: String, size: CGFloat, color: NSColor, in rect: NSRect) {
        let text = NSAttributedString(
            string: value,
            attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color,
            ])
        let textSize = text.size()
        text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
    }
}
