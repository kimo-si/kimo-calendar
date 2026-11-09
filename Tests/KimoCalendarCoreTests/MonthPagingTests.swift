import Testing

@testable import KimoCalendarCore

struct MonthPagingTests {
    // 触控板结束事件仍可能携带位移，跨阈值的最后一段必须参与吸附决策。
    @Test func finalSampleContributesToCommitDistance() throws {
        var drag = MonthDragAccumulator()
        _ = drag.consume(.init(x: -70, y: 0, phase: .began, time: 0))
        let released = drag.consume(.init(x: -30, y: 0, phase: .ended, time: 0.3))
        guard case .settle(let distance, let projected, false) = try #require(released) else {
            Issue.record("未输出正确的抬手事件")
            return
        }
        #expect(distance == -100)
        #expect(destination(distance, projected) == 1)
    }

    // 跟手采样只返回实际位移，达到旧翻页阈值时也不能提前跳月。
    @Test func draggingTracksEverySampleWithoutCommitting() {
        var drag = MonthDragAccumulator()
        #expect(drag.consume(.init(x: -4, y: 0, phase: .began, time: 0)) == nil)
        #expect(drag.consume(.init(x: -4, y: 0, phase: .changed, time: 0.02)) == .tracking(-8))
        #expect(drag.consume(.init(x: -80, y: 0, phase: .changed, time: 0.04)) == .tracking(-88))
        #expect(drag.isHorizontal)
    }

    // 快速轻扫即使位移较小，抬手速度也可以把页面送往邻月。
    @Test func quickFlickCommitsOnRelease() throws {
        var drag = MonthDragAccumulator()
        _ = drag.consume(.init(x: -10, y: 0, phase: .began, time: 0))
        _ = drag.consume(.init(x: -30, y: 0, phase: .changed, time: 0.016))
        let released = drag.consume(.init(x: 0, y: 0, phase: .ended, time: 0.025))
        let result = try #require(released)
        guard case .settle(let distance, let projected, let cancelled) = result else {
            Issue.record("未输出抬手事件")
            return
        }
        #expect(!cancelled)
        #expect(destination(distance, projected) == 1)
        #expect(!drag.isHorizontal)
    }

    // 停住后放手只按当前短距离归位，不沿用此前的高速度误翻页。
    @Test func pausingBeforeReleaseCancelsFlickVelocity() {
        var drag = MonthDragAccumulator()
        _ = drag.consume(.init(x: -10, y: 0, phase: .began, time: 0))
        _ = drag.consume(.init(x: -20, y: 0, phase: .changed, time: 0.016))
        #expect(
            drag.consume(.init(x: 0, y: 0, phase: .ended, time: 0.3))
                == .settle(distance: -30, projected: -30, cancelled: false))
        #expect(destination(-30, -30) == 0)
    }

    // 已锁定的纵向手势不能被后续横向偏斜抢走，下一次横向手势正常。
    @Test func verticalGestureStaysVertical() {
        var drag = MonthDragAccumulator()
        #expect(drag.consume(.init(x: 1, y: 20, phase: .began, time: 0)) == nil)
        #expect(drag.consume(.init(x: -180, y: 1, phase: .changed, time: 0.03)) == nil)
        #expect(drag.consume(.init(x: 0, y: 0, phase: .ended, time: 0.04)) == nil)
        #expect(drag.consume(.init(x: -12, y: 0, phase: .began, time: 1)) == .tracking(-12))
    }

    // 手势取消发出归位事件，并清除序列使反向拖动能够立即开始。
    @Test func cancellationResetsTracking() {
        var drag = MonthDragAccumulator()
        _ = drag.consume(.init(x: -120, y: 0, phase: .began, time: 0))
        #expect(
            drag.consume(.init(x: 0, y: 0, phase: .cancelled, time: 0.2))
                == .settle(distance: -120, projected: -120, cancelled: true))
        #expect(drag.consume(.init(x: 20, y: 0, phase: .began, time: 1)) == .tracking(20))
    }

    // 系统惯性不能继续推动页面或引起一次手势连续翻月。
    @Test func momentumDoesNotMoveOrCommitAnotherPage() {
        var drag = MonthDragAccumulator()
        _ = drag.consume(.init(x: -90, y: 0, phase: .began, time: 0))
        _ = drag.consume(.init(x: 0, y: 0, phase: .ended, time: 0.2))
        #expect(drag.consume(.init(x: -500, y: 0, phase: .changed, time: 0.3, momentum: true)) == nil)
        #expect(drag.consume(.init(x: 0, y: 0, phase: .ended, time: 0.4, momentum: true)) == nil)
        #expect(!drag.isHorizontal)
    }

    // 鼠标的系统预测会参与轻扫判定，不需要额外等待双击或计时器。
    @Test func mousePredictionIsUsedAtRelease() {
        var drag = MonthDragAccumulator()
        _ = drag.consume(.init(x: 20, y: 0, phase: .began, time: 0))
        #expect(
            drag.consume(.init(x: 0, y: 0, phase: .ended, time: 0.1, projectedDistance: 200))
                == .settle(distance: 20, projected: 200, cancelled: false))
        #expect(destination(30, 200) == -1)
    }

    // 长拖动始终只提交一页，左右方向与手指移动一致。
    @Test func longDragCommitsExactlyOnePage() {
        #expect(destination(-120, -120) == 1)
        #expect(destination(120, 120) == -1)
        #expect(destination(-900, -1400) == 1)
        #expect(destination(900, 1400) == -1)
        #expect(destination(-20, -40) == 0)
        #expect(destination(-12, -600) == 0)
    }

    // 正常范围内一比一跟手，最大位移限制在一页以内。
    @Test func displacementFollowsFingerAndClampsToOnePage() {
        #expect(displacement(-73) == -73)
        #expect(displacement(48) == 48)
        #expect(displacement(-900) == -350)
        #expect(displacement(900) == 350)
    }

    // 可浏览年份边界没有空白页，拖动只产生轻微阻力。
    @Test func yearBoundaryResistsAndCannotCommit() {
        #expect(
            MonthPagingPhysics.destination(
                distance: 200, projected: 600, width: 350, canGoBack: false, canGoForward: true) == 0)
        let edge = MonthPagingPhysics.displacement(200, width: 350, canGoBack: false, canGoForward: true)
        #expect(edge > 0 && edge < 10)
        #expect(
            MonthPagingPhysics.destination(
                distance: -200, projected: -600, width: 350, canGoBack: true, canGoForward: false) == 0)
    }

    // 无效几何和非有限输入不会污染页面位移或产生翻页。
    @Test func invalidInputDoesNotProduceMotion() {
        #expect(
            MonthPagingPhysics.destination(
                distance: .nan, projected: 20, width: 350, canGoBack: true, canGoForward: true) == 0)
        #expect(MonthPagingPhysics.displacement(.infinity, width: 350, canGoBack: true, canGoForward: true) == 0)
        #expect(MonthPagingPhysics.displacement(10, width: 0, canGoBack: true, canGoForward: true) == 0)
    }

    // 靠近终点时吸附更短，完整按钮翻页仍保持可控的自然时长。
    @Test func settleDurationDependsOnRemainingTravel() {
        #expect(MonthPagingPhysics.duration(from: 0, to: -350, width: 350) == 0.3)
        #expect(MonthPagingPhysics.duration(from: -330, to: -350, width: 350) == 0.16)
        #expect(MonthPagingPhysics.duration(from: 10, to: 0, width: 0) == 0.16)
    }

    // 使用相同视口验证手势决策，不复制距离阈值实现。
    private func destination(_ distance: Double, _ projected: Double) -> Int {
        MonthPagingPhysics.destination(
            distance: distance, projected: projected, width: 350, canGoBack: true, canGoForward: true)
    }

    // 为位移测试提供可向两侧浏览的视口条件。
    private func displacement(_ distance: Double) -> Double {
        MonthPagingPhysics.displacement(distance, width: 350, canGoBack: true, canGoForward: true)
    }
}
