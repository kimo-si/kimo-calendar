import AppKit

@main
struct KimoCalendarApp {
    // 运行原生菜单栏进程，保持应用代理直到事件循环退出。
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
