import Foundation

public protocol TodoRepository: Sendable {
    // 在明确事务中执行保存、完成、删除或延后操作。
    func apply(_ mutation: TodoMutation, now: Date) async throws -> TodoChange
    // 从一个读取快照返回所选日期与可见月份的统计。
    func snapshot(_ query: TodoSnapshot.Query) async throws -> TodoSnapshot
    // 读取通知操作对应的原始待办，用于定位到日期。
    func item(id: UUID) async throws -> TodoItem?
    // 只读取仍需系统提醒的未来待办。
    func upcomingReminders(after date: Date) async throws -> [TodoItem]
    // 保留仍有效的系统请求，包含睡眠期间已到期但尚待系统投递的提醒。
    func activeReminderIDs() async throws -> Set<UUID>
}
