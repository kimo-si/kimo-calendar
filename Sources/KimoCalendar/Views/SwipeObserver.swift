import KimoCalendarCore
import SwiftUI

struct SwipeObserver: NSViewRepresentable {
    let onUpdate: (MonthDragAccumulator.Update) -> Void

    // 安装只接收本应用滚动事件的监听器，不需要辅助功能权限。
    func makeNSView(context: Context) -> SwipeEventView {
        let view = SwipeEventView()
        view.onUpdate = onUpdate
        return view
    }

    // 及时更新回调，避免视图刷新后仍引用旧状态。
    func updateNSView(_ view: SwipeEventView, context: Context) { view.onUpdate = onUpdate }

    // SwiftUI 销毁面板时显式解除监听，避免隐藏视图仍接收滚动事件。
    static func dismantleNSView(_ view: SwipeEventView, coordinator: ()) { view.stopMonitoring() }
}

@MainActor final class SwipeEventView: NSView {
    var onUpdate: ((MonthDragAccumulator.Update) -> Void)?
    private var monitor: Any?
    private var accumulator = MonthSwipeAccumulator()
    private var drag = MonthDragAccumulator()

    // 仅在视图接入可见窗口时安装监听，离开窗口立即释放。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    // 显式移除本地事件监听，避免闭包生命周期超过面板。
    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    // 仅处理发生在日历网格区域的横向滑动，其他事件正常传递。
    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === window,
            drag.isHorizontal || bounds.contains(convert(event.locationInWindow, from: nil))
        else { return false }
        let phase = gesturePhase(event)
        if phase == .discrete, event.momentumPhase.isEmpty { return handleWheel(event) }
        let wasHorizontal = drag.isHorizontal
        let update = drag.consume(
            .init(
                x: event.scrollingDeltaX, y: event.scrollingDeltaY, phase: phase, time: event.timestamp,
                momentum: !event.momentumPhase.isEmpty))
        if let update { onUpdate?(update) }
        return wasHorizontal || drag.isHorizontal
            || (!event.momentumPhase.isEmpty && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY))
    }

    // 无阶段的普通滚轮仍按单页切换，触控板使用连续位移路径。
    private func handleWheel(_ event: NSEvent) -> Bool {
        let offset = accumulator.consume(
            x: event.scrollingDeltaX, y: event.scrollingDeltaY, phase: .discrete,
            momentum: false, time: event.timestamp)
        if let offset { onUpdate?(.step(offset)) }
        return abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
    }

    // 将 AppKit 手势阶段转换为可独立测试的手势状态。
    private func gesturePhase(_ event: NSEvent) -> MonthSwipeAccumulator.Phase {
        if event.phase.contains(.began) { return .began }
        if event.phase.contains(.ended) { return .ended }
        if event.phase.contains(.cancelled) { return .cancelled }
        return event.phase.isEmpty ? .discrete : .changed
    }
}
