import KimoCalendarCore
import UserNotifications

@MainActor
final class TodoNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    enum Action: Sendable {
        case open(UUID)
        case complete(UUID)
        case snooze(UUID)
    }
    var onAction: (@MainActor @Sendable (Action) async -> Void)?

    // 日历处于前台时也展示系统横幅，而不是静默吞掉提醒。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    // 在进入主线程前提取可发送值，通知框架对象不会跨 actor 传递。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let id = MacTodoNotifications.todoID(response.notification.request.identifier) else { return }
        let action: Action
        switch response.actionIdentifier {
        case MacTodoNotifications.Identifiers.complete: action = .complete(id)
        case MacTodoNotifications.Identifiers.snooze: action = .snooze(id)
        case UNNotificationDefaultActionIdentifier: action = .open(id)
        default: return
        }
        await onAction?(action)
    }
}
