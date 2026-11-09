import Foundation

public struct TodoSnapshot: Equatable, Sendable {
    public let items: [TodoItem]
    public let counts: [DayCount]

    public struct Query: Equatable, Sendable {
        public let day: CivilDate
        public let firstDay: CivilDate
        public let lastDay: CivilDate

        // 将当日列表与当前日历网格的统计范围一起传给存储层。
        public init(day: CivilDate, firstDay: CivilDate, lastDay: CivilDate) {
            self.day = day
            self.firstDay = firstDay
            self.lastDay = lastDay
        }
    }

    public struct DayCount: Equatable, Sendable {
        public let day: CivilDate
        public let unfinished: Int

        // 只返回网格需要的小型聚合结果，避免读出全部待办。
        public init(day: CivilDate, unfinished: Int) {
            self.day = day
            self.unfinished = unfinished
        }
    }

    // 返回同一读取事务中的当天清单及日期标记。
    public init(items: [TodoItem], counts: [DayCount]) {
        self.items = items
        self.counts = counts
    }
}

public enum TodoChange: Equatable, Sendable {
    case saved(TodoItem)
    case deleted(UUID)

    public var id: UUID {
        switch self {
        case .saved(let item): item.id
        case .deleted(let id): id
        }
    }
}
