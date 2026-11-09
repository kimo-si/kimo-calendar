import Testing

@testable import KimoCalendarCore

struct DateClickSequenceTests {
    private let day = CivilDate(year: 2026, month: 11, day: 30)
    private let nextDay = CivilDate(year: 2026, month: 12, day: 1)

    // 单击在同一次调用中立即选中，不依赖等待双击窗口或后台任务。
    @Test func singleClickSelectsImmediately() {
        var sequence = DateClickSequence()
        #expect(action(&sequence, day, count: 1, time: 10) == .select(day))
        #expect(action(&sequence, nextDay, count: 1, time: 10.1) == .select(nextDay))
    }

    // 同一日期的第二次点击打开待办，第三次点击不重复打开。
    @Test func doubleClickOpensOnce() {
        var sequence = DateClickSequence()
        _ = action(&sequence, day, count: 1, time: 10)
        #expect(action(&sequence, day, count: 2, time: 10.1) == .openTodos(day))
        #expect(action(&sequence, day, count: 3, time: 10.2) == .select(day))
    }

    // 首次选中相邻月份会重排格子，第二次点击仍打开首次点击的实际日期。
    @Test func doubleClickPreservesDateAcrossPageChange() {
        var sequence = DateClickSequence()
        #expect(action(&sequence, day, count: 1, time: 10) == .select(day))
        #expect(action(&sequence, nextDay, count: 2, time: 10.1) == .openTodos(day))
    }

    // 没有首次点击、过期或时钟倒退的序列不能误开旧日期。
    @Test func invalidSequenceOnlySelects() {
        var sequence = DateClickSequence()
        #expect(action(&sequence, nextDay, count: 2, time: 10) == .select(nextDay))
        _ = action(&sequence, day, count: 1, time: 10)
        #expect(action(&sequence, nextDay, count: 2, time: 11) == .select(nextDay))
        _ = action(&sequence, day, count: 1, time: 10)
        #expect(action(&sequence, nextDay, count: 2, time: 9) == .select(nextDay))
    }

    // 键盘或辅助功能激活会清空鼠标序列，后续点击不会复用旧日期。
    @Test func keyboardActivationClearsSequence() {
        var sequence = DateClickSequence()
        _ = action(&sequence, day, count: 1, time: 10)
        #expect(action(&sequence, nextDay, count: 0, time: 10.1) == .select(nextDay))
        #expect(action(&sequence, nextDay, count: 2, time: 10.2) == .select(nextDay))
    }

    // 构造系统点击输入，使用固定双击间隔验证逻辑而不让测试真实等待。
    private func action(
        _ sequence: inout DateClickSequence, _ day: CivilDate, count: Int, time: Double
    ) -> DateClickSequence.Action {
        sequence.consume(.init(day: day, clickCount: count, timestamp: time), doubleClickInterval: 0.5)
    }
}
