import Foundation

public struct MonthSwipeAccumulator: Sendable {
    public enum Phase: Sendable { case began, changed, ended, cancelled, discrete }
    private var distance = 0.0
    private var didTurn = false
    private var axis: Axis?
    private var horizontalTravel = 0.0
    private var verticalTravel = 0.0
    private var lastDiscreteTime = -Double.infinity
    public static let threshold = 48.0
    private static let discreteCooldown = 0.4
    private static let axisThreshold = 8.0
    private enum Axis { case horizontal, vertical }

    // 创建单手势单次翻月的累加器。
    public init() {}

    // 累加横向位移，忽略纵向滚动和惯性，避免一次滑动连翻多月。
    public mutating func consume(x: Double, y: Double, phase: Phase, momentum: Bool, time: Double) -> Int? {
        guard !momentum else { return nil }
        if phase == .began { resetGesture() }
        if phase == .ended || phase == .cancelled {
            resetGesture()
            return nil
        }
        guard !didTurn, x != 0 || y != 0 else { return nil }
        if phase == .discrete {
            guard abs(x) > abs(y), time - lastDiscreteTime >= Self.discreteCooldown, abs(x) >= 1 else { return nil }
            lastDiscreteTime = time
            return x < 0 ? 1 : -1
        }
        guard locksHorizontally(x: x, y: y) else { return nil }
        distance += x
        guard abs(distance) >= Self.threshold else { return nil }
        didTurn = true
        return distance < 0 ? 1 : -1
    }

    // 在一次手势开始时锁定主方向，纵向手势中途偏斜也不会触发翻月。
    private mutating func locksHorizontally(x: Double, y: Double) -> Bool {
        if let axis { return axis == .horizontal }
        horizontalTravel += x
        verticalTravel += y
        guard max(abs(horizontalTravel), abs(verticalTravel)) >= Self.axisThreshold else { return false }
        axis = abs(horizontalTravel) > abs(verticalTravel) ? .horizontal : .vertical
        if axis == .horizontal { distance = horizontalTravel - x }
        return axis == .horizontal
    }

    // 每次抬手或取消时清除方向锁，下一次可立即反向翻页。
    private mutating func resetGesture() {
        distance = 0
        didTurn = false
        axis = nil
        horizontalTravel = 0
        verticalTravel = 0
    }
}
