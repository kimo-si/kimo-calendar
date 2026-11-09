import Testing

@testable import KimoCalendarCore

struct MonthSwipeTests {
    // 一个连续手势最多翻一页，惯性不再触发翻页。
    @Test func oneGestureTurnsOneMonth() {
        var swipe = MonthSwipeAccumulator()
        #expect(swipe.consume(x: -20, y: 0, phase: .began, momentum: false, time: 0) == nil)
        #expect(swipe.consume(x: -30, y: 2, phase: .changed, momentum: false, time: 0.1) == 1)
        #expect(swipe.consume(x: -100, y: 0, phase: .changed, momentum: false, time: 0.2) == nil)
        #expect(swipe.consume(x: -100, y: 0, phase: .changed, momentum: true, time: 0.3) == nil)
        #expect(swipe.consume(x: 0, y: 0, phase: .ended, momentum: false, time: 0.4) == nil)
        #expect(swipe.consume(x: 60, y: 0, phase: .began, momentum: false, time: 1) == -1)
    }

    // 纵向滚动和未达阈值的小幅抖动不会翻月。
    @Test func verticalScrollAndJitterDoNotTurn() {
        var swipe = MonthSwipeAccumulator()
        #expect(swipe.consume(x: 10, y: 40, phase: .began, momentum: false, time: 0) == nil)
        #expect(swipe.consume(x: 15, y: 2, phase: .changed, momentum: false, time: 0.1) == nil)
        #expect(swipe.consume(x: -15, y: 2, phase: .changed, momentum: false, time: 0.2) == nil)
        #expect(swipe.consume(x: 0, y: 0, phase: .cancelled, momentum: false, time: 0.3) == nil)
    }

    // 普通鼠标横向滚轮应用冷却时间，连续事件不会高速翻页。
    @Test func discreteWheelHasCooldown() {
        var swipe = MonthSwipeAccumulator()
        #expect(swipe.consume(x: -5, y: 0, phase: .discrete, momentum: false, time: 0) == 1)
        #expect(swipe.consume(x: -5, y: 0, phase: .discrete, momentum: false, time: 0.1) == nil)
        #expect(swipe.consume(x: 5, y: 0, phase: .discrete, momentum: false, time: 1) == -1)
    }

    // 纵向滑动后出现横向偏斜仍不翻月，防止上下滚动误触发横向翻页。
    @Test func verticalGestureCannotBecomeMonthSwipe() {
        var swipe = MonthSwipeAccumulator()
        #expect(swipe.consume(x: 1, y: 20, phase: .began, momentum: false, time: 0) == nil)
        #expect(swipe.consume(x: -80, y: 2, phase: .changed, momentum: false, time: 0.1) == nil)
        #expect(swipe.consume(x: 0, y: 0, phase: .ended, momentum: false, time: 0.2) == nil)
        #expect(swipe.consume(x: -60, y: 0, phase: .began, momentum: false, time: 0.3) == 1)
    }

    // 左右连续反向滑动方向正确，每次手势仅翻一个月份。
    @Test func oppositeHorizontalGesturesTurnOppositeMonths() {
        var swipe = MonthSwipeAccumulator()
        #expect(swipe.consume(x: -60, y: 4, phase: .began, momentum: false, time: 0) == 1)
        #expect(swipe.consume(x: 0, y: 0, phase: .ended, momentum: false, time: 0.1) == nil)
        #expect(swipe.consume(x: 60, y: -4, phase: .began, momentum: false, time: 0.2) == -1)
        #expect(swipe.consume(x: 100, y: 0, phase: .changed, momentum: false, time: 0.3) == nil)
    }

    // 小幅触控板采样仍累计完整位移，方向锁不会吃掉起始阶段的移动。
    @Test func smallHorizontalSamplesKeepTheirDistance() {
        var swipe = MonthSwipeAccumulator()
        #expect(swipe.consume(x: -2, y: 0, phase: .began, momentum: false, time: 0) == nil)
        for step in 1..<23 {
            #expect(swipe.consume(x: -2, y: 0, phase: .changed, momentum: false, time: Double(step) / 100) == nil)
        }
        #expect(swipe.consume(x: -2, y: 0, phase: .changed, momentum: false, time: 0.24) == 1)
    }
}
