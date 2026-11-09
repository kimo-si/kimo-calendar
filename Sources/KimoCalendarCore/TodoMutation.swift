import Foundation

public enum TodoMutation: Sendable {
    case save(Draft)
    case completion(id: UUID, isCompleted: Bool)
    case delete(id: UUID)
    case snooze(id: UUID, until: Date)

    public struct Draft: Sendable {
        public let id: UUID
        public let title: String
        public let day: CivilDate
        public let reminderAt: Date?

        // 显式传输待办编辑内容，编辑时继续使用原有 UUID。
        public init(id: UUID = UUID(), title: String, day: CivilDate, reminderAt: Date? = nil) {
            self.id = id
            self.title = title
            self.day = day
            self.reminderAt = reminderAt
        }

        // 校验标题、日期及提醒时间，禁止把无效编辑写入事务。
        public func validated(now: Date) throws -> Self {
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.count <= 200, !clean.contains("\0") else { throw TodoError.invalidTitle }
            guard CivilDate(iso8601: day.iso8601) != nil,
                CalendarEngine.supportedYears.contains(day.year)
            else { throw TodoError.invalidDate }
            if let reminderAt {
                guard reminderAt.timeIntervalSince1970.isFinite, reminderAt > now else { throw TodoError.pastReminder }
            }
            return Self(id: id, title: clean, day: day, reminderAt: reminderAt)
        }
    }
}

public enum TodoError: Error, LocalizedError, Equatable, Sendable {
    case invalidTitle, invalidDate, pastReminder, missingItem, unsupportedSchema
    case database(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidTitle: "请输入 1 至 200 字的待办标题。"
        case .invalidDate: "请选择有效的待办日期。"
        case .pastReminder: "提醒时间已过，请选择将来的时间。"
        case .missingItem: "这条待办已不存在，请刷新后重试。"
        case .unsupportedSchema: "待办数据由较新版本创建，请更新应用。"
        case .database: "无法读写本地待办，请检查磁盘空间或稍后重试。"
        }
    }
}
