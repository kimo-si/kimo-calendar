import KimoCalendarCore
import SwiftUI

struct MonthGrid: View {
    let days: [DayPresentation]
    let monthID: CivilDate
    let monthTitle: String
    let selectedID: CivilDate?
    let showLunar: Bool
    let showHolidayMarks: Bool
    let previousPage: MonthPagePresentation?
    let nextPage: MonthPagePresentation?
    let requestedPage: Int
    let navigationResetToken: UUID
    let todos: TodoStore
    let onSelect: (DayPresentation) -> Void
    let onOpenTodos: (DayPresentation) -> Void
    let onTurn: (Int) -> Void
    @State private var clickSequence = DateClickSequence()
    @State private var mouseGesture = MonthDragAccumulator()
    @State private var mouseTranslation: CGSize?
    @State private var offset: CGFloat = 0
    @State private var isSettling = false
    @State private var queuedSteps = 0
    @State private var expectedMonth: CivilDate?
    @State private var animationToken = UUID()
    @State private var isActive = false
    @Environment(\.calendarPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(spacing: 3) {
            weekdayHeader
            GeometryReader { geometry in
                ZStack { pageStrip(width: geometry.size.width) }
                    .contentShape(.rect)
                    .background(SwipeObserver { handle($0, width: geometry.size.width) })
                    .simultaneousGesture(mouseDrag(width: geometry.size.width))
                    .onChange(of: requestedPage) { old, new in request(new - old, width: geometry.size.width) }
                    .onChange(of: monthID) { _, new in monthChanged(new, width: geometry.size.width) }
                    .onChange(of: navigationResetToken) { _, _ in resetForNavigation() }
            }
            .frame(height: CalendarTheme.monthRowsHeight)
            .clipped()
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .background(.background.opacity(0.52), in: .rect(cornerRadius: CalendarTheme.corner))
        .clipShape(.rect(cornerRadius: CalendarTheme.corner))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(monthTitle)
        .onAppear { isActive = true }
        .onDisappear(perform: cancelPaging)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 2) {
            ForEach(0..<7) { index in
                Text(Self.weekdays[index])
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(index > 4 ? palette.holiday : .primary.opacity(0.64))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("星期" + Self.weekdays[index])
            }
        }
        .frame(height: 26)
        .background(.primary.opacity(0.025))
    }

    // 三页连续排放并共用同一位移，邻页会随着手指逐步露出。
    private func pageStrip(width: CGFloat) -> some View {
        ZStack {
            if let previousPage {
                page(previousPage.days, selected: nil)
                    .offset(x: -width).allowsHitTesting(false).accessibilityHidden(true)
            }
            page(days, selected: selectedID)
                .allowsHitTesting(offset == 0 && !isSettling)
            if let nextPage {
                page(nextPage.days, selected: nil)
                    .offset(x: width).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .frame(width: width, height: CalendarTheme.monthRowsHeight)
        .offset(x: reduceMotion ? 0 : offset)
        .contentShape(.rect)
    }

    // 每页只读取已缓存的日期和待办计数，手势帧内没有日期计算或磁盘操作。
    private func page(_ days: [DayPresentation], selected: CivilDate?) -> some View {
        MonthDatePage(
            days: days, selectedID: selected, showLunar: showLunar, showHolidayMarks: showHolidayMarks,
            todos: todos, onSelect: handleClick, onOpenTodos: onOpenTodos)
    }

    // 鼠标与触控板使用相同的方向锁和吸附策略，鼠标提供系统预测的抬手距离。
    private func mouseDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in mouseChanged(value, width: width) }
            .onEnded { value in mouseEnded(value, width: width) }
    }

    // 将鼠标绝对拖动换成增量，首次锁定横向后保持一比一跟手。
    private func mouseChanged(_ value: DragGesture.Value, width: CGFloat) {
        let last = mouseTranslation ?? .zero
        let phase: MonthSwipeAccumulator.Phase = mouseTranslation == nil ? .began : .changed
        mouseTranslation = value.translation
        let update = mouseGesture.consume(
            .init(
                x: value.translation.width - last.width, y: value.translation.height - last.height,
                phase: phase, time: value.time.timeIntervalSinceReferenceDate))
        if let update { handle(update, width: width) }
    }

    // 鼠标抬手后按距离和速度决定完成翻页或回到原位。
    private func mouseEnded(_ value: DragGesture.Value, width: CGFloat) {
        let last = mouseTranslation ?? value.translation
        mouseTranslation = nil
        let update = mouseGesture.consume(
            .init(
                x: value.translation.width - last.width, y: value.translation.height - last.height,
                phase: .ended, time: value.time.timeIntervalSinceReferenceDate,
                projectedDistance: value.predictedEndTranslation.width))
        if let update { handle(update, width: width) }
    }

    // 跟手阶段直接更新位移，松手才运行吸附动画，惯性不再额外翻月。
    private func handle(_ update: MonthDragAccumulator.Update, width: CGFloat) {
        if case .step(let step) = update {
            request(step, width: width)
            return
        }
        if isSettling {
            if case .settle(let distance, let projected, false) = update {
                request(destination(distance: distance, projected: projected, width: width), width: width)
            }
            return
        }
        switch update {
        case .tracking(let distance):
            offset = MonthPagingPhysics.displacement(
                distance, width: width, canGoBack: previousPage != nil, canGoForward: nextPage != nil)
        case .settle(let distance, let projected, let cancelled):
            let step =
                cancelled
                ? 0
                : destination(distance: distance, projected: projected, width: width)
            settle(step, width: width)
        case .step: break
        }
    }

    // 当前手势和排队的后续手势使用同一套距离、轻扫和年份边界规则。
    private func destination(distance: Double, projected: Double, width: CGFloat) -> Int {
        MonthPagingPhysics.destination(
            distance: distance, projected: projected, width: width,
            canGoBack: previousPage != nil, canGoForward: nextPage != nil)
    }

    // 连续点击按顺序逐页处理，避免同时堆叠多个月份动画。
    private func request(_ steps: Int, width: CGFloat) {
        queuedSteps += steps
        guard !isSettling, expectedMonth == nil, queuedSteps != 0 else { return }
        let step = queuedSteps > 0 ? 1 : -1
        queuedSteps -= step
        guard step > 0 ? nextPage != nil : previousPage != nil else {
            queuedSteps = 0
            return
        }
        settle(step, width: width)
    }

    // 吸附到整页边界，使用动画完成回调提交月份，不依赖延时计时器。
    private func settle(_ step: Int, width: CGFloat) {
        let target = -CGFloat(step) * width
        let token = UUID()
        animationToken = token
        isSettling = true
        let duration = MonthPagingPhysics.duration(from: offset, to: target, width: width)
        if reduceMotion {
            finish(step, token: token, width: width)
            return
        }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: duration), completionCriteria: .removed) {
            offset = target
        } completion: {
            finish(step, token: token, width: width)
        }
    }

    // 已显示的邻页成为当前页时原子重置位移，交接时内容位置完全一致。
    private func finish(_ step: Int, token: UUID, width: CGFloat) {
        guard isActive, animationToken == token else { return }
        expectedMonth = step > 0 ? nextPage?.month : step < 0 ? previousPage?.month : nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            offset = 0
            isSettling = false
            if step != 0 { onTurn(step) }
        }
        if step == 0 { request(0, width: width) }
    }

    // 内部分页交接后继续排队请求，外部跳转则立即取消旧动画和待执行翻页。
    private func monthChanged(_ newMonth: CivilDate, width: CGFloat) {
        if expectedMonth == newMonth {
            expectedMonth = nil
            request(0, width: width)
        } else {
            resetForNavigation()
        }
    }

    // 即使跳转目标仍是当前月，也立即取消尚未完成的拖动和翻页队列。
    private func resetForNavigation() {
        cancelPaging()
        isActive = true
    }

    // 收起面板或跳转日期后让旧完成回调失效，避免隐藏期间继续翻月。
    private func cancelPaging() {
        isActive = false
        animationToken = UUID()
        queuedSteps = 0
        expectedMonth = nil
        isSettling = false
        offset = 0
        mouseTranslation = nil
        mouseGesture = MonthDragAccumulator()
    }

    // 单击立即选中，双击保留首次点击的日期，辅助功能操作继续使用原生按钮。
    private func handleClick(_ day: DayPresentation) {
        let event = NSApp.currentEvent
        let isMouse = event?.type == .leftMouseUp || event?.type == .leftMouseDown
        let input = DateClickSequence.Input(
            day: day.date, clickCount: isMouse ? event?.clickCount ?? 0 : 0, timestamp: event?.timestamp ?? 0)
        switch clickSequence.consume(input, doubleClickInterval: NSEvent.doubleClickInterval) {
        case .select: onSelect(day)
        case .openTodos(let date):
            guard let target = days.first(where: { $0.date == date }) else { return }
            onOpenTodos(target)
        }
    }
}
