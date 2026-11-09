import AppKit

@main
struct IconGenerator {
    // 将应用包使用的红白日历图标导出为 macOS 所需的多种分辨率。
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw CocoaError(.fileWriteInvalidFileName) }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            try writeIcon(size: points, to: directory.appending(path: "icon_\(points)x\(points).png"))
            try writeIcon(size: points * 2, to: directory.appending(path: "icon_\(points)x\(points)@2x.png"))
        }
    }

    // 使用明确的像素缓冲区导出，避免 Retina 屏幕改变图标实际分辨率。
    private static func writeIcon(size: Int, to destination: URL) throws {
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let bounds = NSRect(x: 0, y: 0, width: size, height: size)
        CalendarIconRenderer.image(for: .now, size: bounds.size, style: .application).draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: destination, options: .atomic)
    }
}
