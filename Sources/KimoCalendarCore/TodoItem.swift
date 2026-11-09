import Foundation

public struct TodoItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let day: CivilDate
    public let reminderAt: Date?
    public let isCompleted: Bool
    public let createdAt: Date
    public let updatedAt: Date

    // 创建与数据库及通知共享稳定标识的待办值对象。
    public init(
        id: UUID, title: String, day: CivilDate, reminderAt: Date?, isCompleted: Bool,
        createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.day = day
        self.reminderAt = reminderAt
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
