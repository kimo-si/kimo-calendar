import Foundation

public struct MonthDragAccumulator: Sendable {
    public struct Sample: Sendable {
        public let x: Double
        public let y: Double
        public let phase: MonthSwipeAccumulator.Phase
        public let time: Double
        public let projectedDistance: Double?
        public let momentum: Bool

        // 同时接收鼠标位移差和触控板采样，预测距离仅由鼠标抬手时提供。
        public init(
            x: Double, y: Double, phase: MonthSwipeAccumulator.Phase, time: Double,
            projectedDistance: Double? = nil, momentum: Bool = false
        ) {
            self.x = x
            self.y = y
            self.phase = phase
            self.time = time
            self.projectedDistance = projectedDistance
            self.momentum = momentum
        }
    }

    public enum Update: Equatable, Sendable {
        case tracking(Double)
        case settle(distance: Double, projected: Double, cancelled: Bool)
        case step(Int)
    }

    private enum Axis { case horizontal, vertical }
    private var axis: Axis?
    private var x = 0.0
    private var y = 0.0
    private var velocity = 0.0
    private var lastTime: Double?
    private var lastMotionTime = 0.0
    public var isHorizontal: Bool { axis == .horizontal }
    private static let axisThreshold = 8.0
    private static let projectionTime = 0.16
    private static let staleVelocityTime = 0.10
    private static let maximumVelocity = 1800.0

    // 每个输入源持有独立手势状态，空闲时没有计时器。
    public init() {}

    // 位移采样只更新跟手位置，抬手或取消时才发出一次吸附决定。
    public mutating func consume(_ sample: Sample) -> Update? {
        guard !sample.momentum, sample.x.isFinite, sample.y.isFinite, sample.time.isFinite else { return nil }
        if sample.phase == .began { self = Self() }
        if sample.phase == .ended || sample.phase == .cancelled {
            if sample.x != 0 || sample.y != 0 { accumulate(sample) }
            return finish(sample)
        }
        guard sample.phase != .discrete else { return nil }
        accumulate(sample)
        return isHorizontal ? .tracking(x) : nil
    }

    // 同时累计普通和抬手采样，最后一段位移不能被结束阶段吃掉。
    private mutating func accumulate(_ sample: Sample) {
        x += sample.x
        y += sample.y
        if axis == nil, max(abs(x), abs(y)) >= Self.axisThreshold {
            axis = abs(x) > abs(y) ? .horizontal : .vertical
        }
        updateVelocity(sample)
    }

    // 短暂停住后放手不沿用旧速度，取消手势始终归位。
    private mutating func finish(_ sample: Sample) -> Update? {
        defer { self = Self() }
        guard isHorizontal else { return nil }
        let speed = sample.time - lastMotionTime <= Self.staleVelocityTime ? velocity : 0
        let prediction = sample.projectedDistance.flatMap { $0.isFinite ? $0 : nil }
        return .settle(
            distance: x, projected: prediction ?? x + speed * Self.projectionTime,
            cancelled: sample.phase == .cancelled)
    }

    // 只使用真实采样间隔估计速度，并限制异常事件造成的投射距离。
    private mutating func updateVelocity(_ sample: Sample) {
        if let lastTime, sample.time > lastTime {
            let measured = sample.x / max(0.008, sample.time - lastTime)
            velocity = velocity * 0.4 + min(Self.maximumVelocity, max(-Self.maximumVelocity, measured)) * 0.6
        }
        lastTime = sample.time
        if abs(sample.x) > 0.1 { lastMotionTime = sample.time }
    }
}
