import KimoCalendarCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = CalendarModel()
    private let popover = NSPopover()
    private let notificationDelegate = TodoNotificationDelegate()
    private var statusItem: NSStatusItem?
    private var midnightTimer: Timer?
    private var previewWindow: NSWindow?
    private var isClosingPopover = false
    private var reopenAfterClosing = false
    private var todoDayAfterClosing: CivilDate?

    // 以无 Dock 图标的原生菜单栏应用启动，只在用户打开时创建面板。
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        configureTodoNotifications()
        observeClock()
        scheduleMidnight()
        if ProcessInfo.processInfo.arguments.contains("--preview") { openPreview() }
    }

    // 用户再次打开应用时直接显示日历，避免看似没有响应。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let previewWindow, previewWindow.isVisible {
            if model.presentedTodoDay == nil, !model.showMonthPicker { previewWindow.makeKeyAndOrderFront(nil) }
            return false
        }
        if isClosingPopover || !popover.isShown { showPopover() }
        return false
    }

    // 退出时撤销事件源，菜单栏不遗留无效图标。
    func applicationWillTerminate(_ notification: Notification) {
        midnightTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    // 在系统开始收缩时记录状态，防止快速连点重建尚未关闭的面板。
    func popoverWillClose(_ notification: Notification) {
        isClosingPopover = true
    }

    // 关闭前读取最新动态效果偏好，覆盖菜单栏、Escape 和点外部关闭。
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        updateAnimationPreferences()
        return true
    }

    // 等收缩动画完全结束后再释放视图，避免动画中出现空白或闪烁。
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
        model.isPinned = false
        model.showMonthPicker = false
        model.showSettings = false
        model.presentedTodoDay = nil
        isClosingPopover = false
        guard reopenAfterClosing else { return }
        reopenAfterClosing = false
        let todoDay = todoDayAfterClosing
        todoDayAfterClosing = nil
        // 当前关闭回调返回后再响应重开，避免打断 AppKit 的窗口清理。
        Task { @MainActor [weak self] in self?.showPopover(todoDay: todoDay) }
    }

    // 区分菜单栏左右键；左键开关日历，右键显示快速操作。
    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if isClosingPopover {
            reopenAfterClosing.toggle()
            todoDayAfterClosing = nil
            return
        }
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    // 创建固定宽度的日期图标，不运行每秒刷新的时钟。
    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 28)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        updateStatusIcon()
    }

    // 使用系统锚点动画展开和收缩，保留原生阴影及 Escape 关闭行为。
    private func configurePopover() {
        popover.behavior = .transient
        updateAnimationPreferences()
        popover.contentSize = NSSize(width: CalendarTheme.width, height: CalendarTheme.height)
        popover.delegate = self
    }

    // 由系统驱动合成动画；用户开启减少动态效果时直接切换，不持续刷新。
    private func updateAnimationPreferences() {
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // 普通展开回到今天；通知展开定位事项日期，并保留收缩过程中的重开目标。
    private func showPopover(todoDay: CivilDate? = nil) {
        if isClosingPopover {
            reopenAfterClosing = true
            todoDayAfterClosing = todoDay
            return
        }
        if popover.isShown {
            if let todoDay {
                model.focusTodoDay(todoDay)
                model.presentedTodoDay = todoDay
            }
            return
        }
        guard let button = statusItem?.button else { return }
        // 在创建视图前完成日期定位，展开动画不会先显示上次浏览的月份。
        preparePopoverDate(todoDay)
        // 每次打开读取系统偏好，保证无需重启即可切换减少动态效果。
        updateAnimationPreferences()
        popover.behavior = model.isPinned ? .applicationDefined : .transient
        popover.contentViewController = NSHostingController(rootView: panel())
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
        model.presentedTodoDay = todoDay
    }

    // 刷新系统日期与时区，只有通知入口覆盖默认的今天定位。
    private func preparePopoverDate(_ todoDay: CivilDate?) {
        model.refreshClock()
        if let todoDay { model.focusTodoDay(todoDay) } else { model.goToToday() }
    }

    // 将固定状态应用到系统面板，同时保持单一视图模型。
    private func panel() -> CalendarPanel {
        CalendarPanel(
            model: model,
            onPinChange: { [weak self] pinned in
                self?.popover.behavior = pinned ? .applicationDefined : .transient
            },
            onClose: { [weak self] in self?.closePanel() }
        )
    }

    // 启动时安装通知响应，权限请求仍由用户设置提醒时触发。
    private func configureTodoNotifications() {
        notificationDelegate.onAction = { [weak self] action in await self?.handleTodoNotification(action) }
        MacTodoNotifications.configure(delegate: notificationDelegate)
        Task { await model.todos.reconcile() }
    }

    // 系统通知中的完成、延后及打开操作复用同一事务与提醒协调链。
    private func handleTodoNotification(_ action: TodoNotificationDelegate.Action) async {
        switch action {
        case .complete(let id):
            await model.todos.perform(.completion(id: id, isCompleted: true))
        case .snooze(let id):
            await model.todos.perform(.snooze(id: id, until: .now.addingTimeInterval(10 * 60)))
        case .open(let id):
            guard let item = await model.todos.item(id: id) else { return }
            showPopover(todoDay: item.day)
        }
    }

    // Escape 统一走系统收缩关闭流程，固定面板也可直接关闭。
    private func closePanel() {
        if let previewWindow, previewWindow.isVisible {
            previewWindow.performClose(nil)
            return
        }
        popover.performClose(nil)
    }

    // 绘制更矮的纯数字模板图标，仅在日期变化时更新日号。
    private func updateStatusIcon() {
        let day = String(model.engine.civilDate(.now).day)
        statusItem?.button?.image = CalendarIconRenderer.image(
            for: .now, size: CalendarIconRenderer.menuBarSize, style: .menuBar)
        statusItem?.button?.toolTip = "Kimo 日历 · 点击查看农历和放假安排"
        statusItem?.button?.setAccessibilityLabel("Kimo 日历，今天\(day)日")
    }

    // 订阅跨日、时区、系统时间和唤醒事件，不用高频轮询。
    private func observeClock() {
        let center = NotificationCenter.default
        for name in [NSNotification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
            center.addObserver(self, selector: #selector(clockDidChange), name: name, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(clockDidChange), name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    // 系统日期变化时刷新日期图标与可见网格，并重新计算下一次午夜。
    @objc private func clockDidChange(_ notification: Notification) {
        refreshClock()
    }

    // 让计时器使用自身类型的回调，避免把 Timer 错当作 Notification 桥接。
    @objc private func midnightReached(_ timer: Timer) {
        refreshClock()
    }

    // 统一系统通知与午夜计时器触发后的刷新流程。
    private func refreshClock() {
        model.refreshClock()
        updateStatusIcon()
        scheduleMidnight()
        Task { await model.todos.reconcile() }
    }

    // 单次定时器定位到下一个本地午夜，隐藏期间没有每秒或每分钟任务。
    private func scheduleMidnight() {
        midnightTimer?.invalidate()
        let calendar = Calendar.autoupdatingCurrent
        guard let next = calendar.nextDate(after: .now, matching: DateComponents(hour: 0), matchingPolicy: .nextTime)
        else { return }
        let timer = Timer(
            fireAt: next, interval: 0, target: self,
            selector: #selector(midnightReached), userInfo: nil, repeats: false)
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }

    // 提供无需打开设置的菜单栏快速退出入口。
    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 Kimo 日历", action: #selector(openFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Kimo 日历", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.first?.target = self
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // 菜单关闭后打开日历，避免同时显示两个系统弹出层。
    @objc private func openFromMenu() { showPopover() }

    // 开发预览复用真实界面，便于独立检查布局与辅助功能。
    private func openPreview() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--date"), arguments.indices.contains(index + 1),
            let date = CivilDate(iso8601: arguments[index + 1])
        {
            model.jump(year: date.year, month: date.month)
            if let day = model.days.first(where: { $0.date == date }) { model.select(day) }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: CalendarTheme.width, height: CalendarTheme.height),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Kimo 日历"
        window.contentViewController = NSHostingController(rootView: panel())
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        previewWindow = window
        NSApp.activate()
    }
}
