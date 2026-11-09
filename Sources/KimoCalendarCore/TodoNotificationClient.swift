import Foundation

public enum TodoNotificationPermission: Sendable, Equatable {
    case notDetermined, allowed, denied, unavailable
}

public enum TodoReminderStatus: Sendable, Equatable {
    case notNeeded, scheduled, permissionRequired, unavailable, failed
}

public protocol TodoNotificationClient: Sendable {
    // 只查询权限，不在启动、唤醒或浏览日历时弹出授权请求。
    func permission() async -> TodoNotificationPermission
    // 仅响应用户首次设置提醒或主动开启通知的操作。
    func requestPermission() async throws -> Bool
    // 获取实际已安排的通知标识，UI 据此显示真实状态。
    func pendingIDs() async -> Set<UUID>
    // 用待办稳定标识替换同一条提醒，避免重复通知。
    func schedule(_ item: TodoItem) async throws
    // 同时取消未来提醒与已经投递的通知。
    func cancel(_ ids: Set<UUID>) async
}
