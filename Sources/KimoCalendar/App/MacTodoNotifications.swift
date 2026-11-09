import KimoCalendarCore
import UserNotifications

final class MacTodoNotifications: TodoNotificationClient, Sendable {
    enum Identifiers {
        static let prefix = "kimo.todo."
        static let category = "KIMO_TODO_REMINDER"
        static let complete = "KIMO_TODO_COMPLETE"
        static let snooze = "KIMO_TODO_SNOOZE"
        static let test = "kimo.notification-test"
    }

    // 命令行预览不具备应用通知身份，使用可解释的降级实现，避免框架异常。
    static func make() -> any TodoNotificationClient {
        Bundle.main.bundleURL.pathExtension == "app" ? MacTodoNotifications() : UnavailableTodoNotifications()
    }

    // 在应用启动阶段注册系统通知代理与快捷操作，不申请通知权限。
    @MainActor static func configure(delegate: any UNUserNotificationCenterDelegate) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        let done = UNNotificationAction(identifier: Identifiers.complete, title: "完成", options: [])
        let snooze = UNNotificationAction(identifier: Identifiers.snooze, title: "10分钟后提醒", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Identifiers.category, actions: [done, snooze], intentIdentifiers: [], options: [])
        ])
    }

    // 将系统授权状态转换为与 UI 无关的领域状态。
    func permission() async -> TodoNotificationPermission {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    // 只请求待办需要的横幅和声音，不申请无关访问权限。
    func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    // 只返回当前应用的待办通知，忽略其他用途的请求。
    func pendingIDs() async -> Set<UUID> {
        Set(
            await UNUserNotificationCenter.current().pendingNotificationRequests().compactMap {
                Self.todoID($0.identifier)
            })
    }

    // 以完整绝对时刻安排一次性通知，由 macOS 在应用退出后继续管理。
    func schedule(_ item: TodoItem) async throws {
        guard let date = item.reminderAt, date > .now else { throw TodoError.pastReminder }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = "\(item.day.month)月\(item.day.day)日的待办事项"
        content.sound = .default
        content.categoryIdentifier = Identifiers.category
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.calendar = calendar
        components.timeZone = .gmt
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: Identifiers.prefix + item.id.uuidString,
            content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }

    // 已完成或删除时同时清理通知中心中的旧提醒，避免继续提示。
    func cancel(_ ids: Set<UUID>) async {
        let center = UNUserNotificationCenter.current()
        let identifiers = ids.map { Identifiers.prefix + $0.uuidString }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // 设置页允许主动验证系统通知，不写入真实待办或申请额外权限。
    static func sendTest() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Kimo 日历提醒已开启"
        content.body = "待办到期后，会像这样提醒你。"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Identifiers.test, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        try await UNUserNotificationCenter.current().add(request)
    }

    // 仅检查本应用测试通知的实际投递记录，不读取其他应用的通知内容。
    static func wasTestDelivered() async -> Bool {
        await UNUserNotificationCenter.current().deliveredNotifications().contains {
            $0.request.identifier == Identifiers.test
        }
    }

    // 从稳定请求标识读取待办 UUID，不依赖标题和通知显示语言。
    static func todoID(_ identifier: String) -> UUID? {
        guard identifier.hasPrefix(Identifiers.prefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(Identifiers.prefix.count)))
    }
}

private struct UnavailableTodoNotifications: TodoNotificationClient {
    // 在未打包的开发预览中明确报告通知不可用。
    func permission() async -> TodoNotificationPermission { .unavailable }
    // 不在无应用身份的进程中调用系统授权接口。
    func requestPermission() async throws -> Bool { false }
    // 无通知身份时没有已安排的待办请求。
    func pendingIDs() async -> Set<UUID> { [] }
    // 将不可用状态传回协调层，不伪造提醒成功。
    func schedule(_ item: TodoItem) async throws { throw TodoError.missingItem }
    // 开发预览的撤销不产生系统副作用。
    func cancel(_ ids: Set<UUID>) async {}
}
