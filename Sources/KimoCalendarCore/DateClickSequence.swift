import Foundation

public struct DateClickSequence: Sendable {
    public struct Input: Sendable {
        public let day: CivilDate
        public let clickCount: Int
        public let timestamp: TimeInterval

        // 接收系统已识别的点击次数和单调时间，不启动等待任务或计时器。
        public init(day: CivilDate, clickCount: Int, timestamp: TimeInterval) {
            self.day = day
            self.clickCount = clickCount
            self.timestamp = timestamp
        }
    }

    public enum Action: Equatable, Sendable {
        case select(CivilDate)
        case openTodos(CivilDate)
    }

    private var firstClick: Input?

    // 为每次日历展开建立独立点击序列。
    public init() {}

    // 第一次点击立即返回选中；有效第二次点击打开原日期，避免翻月后位置变化导致误开。
    public mutating func consume(_ input: Input, doubleClickInterval: TimeInterval) -> Action {
        defer { firstClick = input.clickCount == 1 && input.timestamp.isFinite ? input : nil }
        guard input.clickCount == 2, let firstClick,
            input.timestamp.isFinite, doubleClickInterval.isFinite, doubleClickInterval > 0,
            input.timestamp >= firstClick.timestamp,
            input.timestamp - firstClick.timestamp <= doubleClickInterval
        else { return .select(input.day) }
        return .openTodos(firstClick.day)
    }
}
