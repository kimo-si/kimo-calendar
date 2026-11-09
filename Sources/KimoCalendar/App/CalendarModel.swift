import Foundation
import KimoCalendarCore
import Observation

@MainActor @Observable
final class CalendarModel {
    private(set) var engine = CalendarEngine()
    private(set) var displayedMonth: Date
    private(set) var selectedDate: Date
    private(set) var today: Date
    private(set) var days: [DayPresentation] = []
    private(set) var previousPage: MonthPagePresentation?
    private(set) var nextPage: MonthPagePresentation?
    private(set) var upcoming: [CalendarEvent] = []
    private(set) var selectedDay: DayPresentation?
    private(set) var syncResults: [HolidayLoadResult] = []
    private(set) var isSyncing = false
    private(set) var isMovingForward = true
    private(set) var pagingResetToken = UUID()
    var isPinned = false
    var showSettings = false
    var showMonthPicker = false
    var presentedTodoDay: CivilDate?
    let todos = TodoStore()
    var applicationMessage: String?
    var showLunar: Bool { didSet { defaults.set(showLunar, forKey: Keys.lunar) } }
    var showHolidayMarks: Bool { didSet { defaults.set(showHolidayMarks, forKey: Keys.marks) } }
    var automaticSync: Bool { didSet { defaults.set(automaticSync, forKey: Keys.sync) } }
    var appearance: CalendarAppearance { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    var style: CalendarStyle { didSet { defaults.set(style.rawValue, forKey: Keys.style) } }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let repository: HolidayRepository
    @ObservationIgnored private var holidayIndex = HolidayIndex(years: [])
    @ObservationIgnored private var solarEvents: [CalendarEvent] = []
    @ObservationIgnored private var loadToken = UUID()

    var year: Int { engine.gregorian.component(.year, from: displayedMonth) }
    var month: Int { engine.gregorian.component(.month, from: displayedMonth) }
    var monthTitle: String { "\(year)年\(month)月" }
    var monthPageID: CivilDate { CivilDate(year: year, month: month, day: 1) }
    var monthSubtitle: String { engine.monthSubtitle(displayedMonth) }
    var selectedID: CivilDate { engine.civilDate(selectedDate) }
    var visibleSelectedID: CivilDate? {
        let selected = selectedID
        return selected.year == year && selected.month == month ? selected : nil
    }
    var selectedLunar: String { engine.lunarFullDate(selectedDate) }
    var selectedLunarYear: String { engine.lunarYear(selectedDate) }
    var selectedWeekday: String { Self.weekdays[engine.gregorian.component(.weekday, from: selectedDate) - 1] }
    var selectedTitle: String { "\(selectedID.month)月\(selectedID.day)日" }
    var relevantResult: HolidayLoadResult? { syncResults.first { $0.year == year } }
    var sourceURL: URL? { relevantResult?.data?.papers.first }
    var canGoBack: Bool { year > CalendarEngine.supportedYears.lowerBound || month > 1 }
    var canGoForward: Bool { year < CalendarEngine.supportedYears.upperBound || month < 12 }

    // 恢复轻量偏好并创建后台数据仓库；初次渲染不等待网络。
    init(now: Date = .now, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        today = now
        selectedDate = now
        displayedMonth = now
        showLunar = defaults.object(forKey: Keys.lunar) as? Bool ?? true
        showHolidayMarks = defaults.object(forKey: Keys.marks) as? Bool ?? true
        automaticSync = defaults.object(forKey: Keys.sync) as? Bool ?? true
        appearance = CalendarAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        style = CalendarStyle(rawValue: defaults.string(forKey: Keys.style) ?? "") ?? .lavender
        repository = HolidayRepository(
            bundleDirectory: Bundle.module.url(forResource: "Holidays", withExtension: nil),
            cacheDirectory: URL.cachesDirectory.appending(path: "com.kimo.calendar/holidays")
        )
        // 只为当前月份构建日期网格，避免预创建大量月份视图。
        rebuildMonth()
        rebuildUpcoming()
    }

    // 只移动正在浏览的月份，保留实际选中日期，不将日号迁移到目标月份。
    func turnMonth(_ offset: Int) {
        guard let date = engine.moving(displayedMonth, months: offset) else { return }
        presentedTodoDay = nil
        // 在更换月份前确定水平滑入方向，日期格子不再逐个上下重排。
        setDisplayedMonth(date)
        rebuildMonth()
    }

    // 选择网格日期，点击相邻月份的日期时一并切换月份。
    func select(_ day: DayPresentation) {
        guard CalendarEngine.supportedYears.contains(day.date.year) else { return }
        pagingResetToken = UUID()
        selectedDate = day.instant
        setDisplayedMonth(day.instant)
        if day.isCurrentMonth { selectedDay = day } else { rebuildMonth() }
    }

    // 年月选择器只切换浏览月份，不自动选中目标月份的第一天。
    func jump(year: Int, month: Int) {
        guard CalendarEngine.supportedYears.contains(year), (1...12).contains(month) else { return }
        pagingResetToken = UUID()
        presentedTodoDay = nil
        setDisplayedMonth(engine.date(CivilDate(year: year, month: month, day: 1)))
        showMonthPicker = false
        rebuildMonth()
    }

    // 双击日期或使用辅助功能操作时打开当日待办，保持主日历的固定尺寸。
    func openTodos(_ day: DayPresentation) {
        select(day)
        presentedTodoDay = day.date
    }

    // 通知点击定位到对应日期，完整复用年月切换与日期高亮。
    func focusTodoDay(_ day: CivilDate) {
        guard CalendarEngine.supportedYears.contains(day.year) else { return }
        pagingResetToken = UUID()
        selectedDate = engine.date(day)
        setDisplayedMonth(selectedDate)
        showSettings = false
        rebuildMonth()
    }

    // 将可见网格与所选日期一次传给后台，避免每个格子发起数据库查询。
    func loadTodos(on day: CivilDate? = nil) async {
        let query = TodoSnapshot.Query(
            day: day ?? selectedID,
            firstDay: previousPage?.days.first?.date ?? days.first?.date ?? selectedID,
            lastDay: nextPage?.days.last?.date ?? days.last?.date ?? selectedID)
        await todos.refresh(query)
    }

    // 回到系统今天，同时恢复节日列表和高亮。
    func goToToday() {
        pagingResetToken = UUID()
        presentedTodoDay = nil
        today = .now
        selectedDate = today
        setDisplayedMonth(today)
        rebuildMonth()
        rebuildUpcoming()
    }

    // 只在浏览并选中今天时跨午夜跟随，后台唤醒不打断其他月份的浏览。
    func refreshClock() {
        let followedToday = visibleSelectedID != nil && engine.gregorian.isDate(selectedDate, inSameDayAs: today)
        engine = CalendarEngine()
        today = .now
        if followedToday {
            selectedDate = today
            setDisplayedMonth(today)
        }
        rebuildMonth()
        rebuildUpcoming()
    }

    // 先加载相邻三年离线数据，再按偏好检查更新，避免网络阻塞界面。
    func loadHolidays(force: Bool = false) async {
        let token = UUID()
        loadToken = token
        isSyncing = false
        let years = [year - 1, year, year + 1]
        var local: [HolidayLoadResult] = []
        for year in years { local.append(await repository.local(year: year)) }
        guard !Task.isCancelled, loadToken == token else { return }
        applyResults(local)
        guard automaticSync || force else { return }
        isSyncing = true
        // 独立年份并行下载，旧月份的响应通过令牌隔离，不覆盖新月份状态。
        let refreshed = await refreshYears(years, force: force)
        guard loadToken == token else { return }
        isSyncing = false
        guard !Task.isCancelled else { return }
        applyResults(refreshed)
    }

    // 返回即将到来的节日距离系统今天的天数。
    func countdown(_ event: CalendarEvent) -> Int {
        engine.days(from: today, to: engine.date(event.date))
    }

    // 所有跨月入口共用方向判断，兼容跨年、年月选择及回到今天。
    private func setDisplayedMonth(_ date: Date) {
        let order = engine.gregorian.compare(date, to: displayedMonth, toGranularity: .month)
        if order != .orderedSame { isMovingForward = order == .orderedDescending }
        displayedMonth = date
    }

    // 用结构化任务组下载三个年份，关闭面板后自动传播取消请求。
    private func refreshYears(_ years: [Int], force: Bool) async -> [HolidayLoadResult] {
        let repository = repository
        return await withTaskGroup(of: HolidayLoadResult.self) { group in
            for year in years {
                group.addTask { await repository.refresh(year: year, force: force) }
            }
            var results: [HolidayLoadResult] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.year < $1.year }
        }
    }

    // 原子替换视图使用的假日索引，再刷新当前网格与选中日期。
    private func applyResults(_ results: [HolidayLoadResult]) {
        syncResults = results
        holidayIndex = HolidayIndex(years: results.compactMap(\.data))
        rebuildMonth()
    }

    // 仅缓存当前和相邻两个月，滑动过程中不计算农历或访问磁盘。
    private func rebuildMonth() {
        let calculator = SolarTermCalculator(engine: engine)
        solarEvents = [year - 1, year, year + 1].flatMap { calculator.events(year: $0) }
        days = makePage(displayedMonth).days
        previousPage = engine.moving(displayedMonth, months: -1).map(makePage)
        nextPage = engine.moving(displayedMonth, months: 1).map(makePage)
        if let selected = days.first(where: { $0.date == selectedID }) { selectedDay = selected }
    }

    // 各页按自己的月份判断补位日期，邻页滑入时明暗状态保持一致。
    private func makePage(_ date: Date) -> MonthPagePresentation {
        let civil = engine.civilDate(date)
        let month = CivilDate(year: civil.year, month: civil.month, day: 1)
        let days = engine.monthDates(containing: date).map { makeDay($0, month: month) }
        return MonthPagePresentation(month: month, days: days)
    }

    // 日期变化时才计算节日列表，视图重绘不扫描全年。
    private func rebuildUpcoming() {
        upcoming = FestivalCalendar(engine: engine).upcoming(from: today)
    }

    // 合并公历、农历、节日和假日标记，保持视图只负责展示。
    private func makeDay(_ date: Date, month: CivilDate) -> DayPresentation {
        let civil = engine.civilDate(date)
        let festival = FestivalCalendar(engine: engine).festival(on: date)
        let event = festival ?? solarEvents.first { $0.date == civil }
        return DayPresentation(
            date: civil, instant: date, lunar: engine.lunarLabel(date), event: event,
            holiday: holidayIndex.day(civil), isCurrentMonth: civil.month == month.month && civil.year == month.year,
            isToday: engine.gregorian.isDate(date, inSameDayAs: today),
            isWeekend: engine.gregorian.isDateInWeekend(date)
        )
    }

    private static let weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
    private enum Keys {
        static let lunar = "calendar.showLunar"
        static let marks = "calendar.showHolidayMarks"
        static let sync = "calendar.automaticSync"
        static let appearance = "calendar.appearance"
        static let style = "calendar.style"
    }
}
