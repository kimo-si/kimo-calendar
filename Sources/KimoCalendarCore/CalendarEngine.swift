import Foundation

public struct CalendarEngine: Sendable {
    public static let supportedYears = 1901...2099
    public let gregorian: Calendar
    public let chinese: Calendar

    // 统一公历与农历时区，以系统当地日期呈现中国节日。
    public init(timeZone: TimeZone = .autoupdatingCurrent) {
        var solar = Calendar(identifier: .gregorian)
        solar.timeZone = timeZone
        solar.locale = Locale(identifier: "zh_CN")
        solar.firstWeekday = 2
        gregorian = solar
        var lunar = Calendar(identifier: .chinese)
        lunar.timeZone = timeZone
        chinese = lunar
    }

    // 将系统时间转换为可索引的民用日期。
    public func civilDate(_ date: Date) -> CivilDate {
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return CivilDate(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    // 使用当地中午表示日历日期，避免夏令时切换时的午夜缺失。
    public func date(_ civil: CivilDate) -> Date {
        gregorian.date(from: DateComponents(year: civil.year, month: civil.month, day: civil.day, hour: 12))
            ?? Date(timeIntervalSince1970: 0)
    }

    // 生成星期一开头的固定六周网格，让切月时面板高度保持稳定。
    public func monthDates(containing date: Date) -> [Date] {
        guard let first = gregorian.dateInterval(of: .month, for: date)?.start else { return [] }
        let offset = (gregorian.component(.weekday, from: first) + 5) % 7
        guard let start = gregorian.date(byAdding: .day, value: -offset, to: first) else { return [] }
        return (0..<42).compactMap { gregorian.date(byAdding: .day, value: $0, to: start) }
    }

    // 在月份边界内翻页，并将超出目标月份的日期夹取到月末。
    public func moving(_ date: Date, months: Int) -> Date? {
        guard let result = gregorian.date(byAdding: .month, value: months, to: date),
            Self.supportedYears.contains(gregorian.component(.year, from: result))
        else { return nil }
        return result
    }

    // 返回从起点到终点的公历天数，避免用固定秒数处理夏令时。
    public func days(from start: Date, to end: Date) -> Int {
        gregorian.dateComponents(
            [.day], from: gregorian.startOfDay(for: start),
            to: gregorian.startOfDay(for: end)
        ).day ?? 0
    }

    // 以农历月名替换初一，其他日期显示农历日名。
    public func lunarLabel(_ date: Date) -> String {
        let parts = chinese.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard let month = parts.month, let day = parts.day else { return "" }
        return day == 1 ? lunarMonth(month, leap: parts.isLeapMonth == true) : Self.lunarDays[day - 1]
    }

    // 返回选中日期的完整农历月份与日期。
    public func lunarFullDate(_ date: Date) -> String {
        let parts = chinese.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard let month = parts.month, let day = parts.day else { return "" }
        return lunarMonth(month, leap: parts.isLeapMonth == true) + Self.lunarDays[day - 1]
    }

    // 根据系统农历纪年计算干支与生肖，不用公历年份推算春节前的生肖。
    public func lunarYear(_ date: Date) -> String {
        let year = chinese.component(.year, from: date) - 1
        return Self.stems[year % 10] + Self.branches[year % 12] + "年 · 生肖" + Self.animals[year % 12]
    }

    // 展示本月覆盖的农历月份，包括闰月标记。
    public func monthSubtitle(_ date: Date) -> String {
        guard let interval = gregorian.dateInterval(of: .month, for: date) else { return "" }
        let first = chinese.dateComponents([.month, .isLeapMonth], from: interval.start)
        let last = chinese.dateComponents([.month, .isLeapMonth], from: interval.end.addingTimeInterval(-1))
        let start = lunarMonth(first.month ?? 1, leap: first.isLeapMonth == true)
        let end = lunarMonth(last.month ?? 1, leap: last.isLeapMonth == true)
        return lunarYear(date).replacingOccurrences(of: " · 生肖", with: "") + "  " + start
            + (start == end ? "" : " – " + end)
    }

    // 返回农历月名并保留闰月信息。
    private func lunarMonth(_ month: Int, leap: Bool) -> String {
        (leap ? "闰" : "") + Self.lunarMonths[month - 1] + "月"
    }

    private static let stems = Array("甲乙丙丁戊己庚辛壬癸").map(String.init)
    private static let branches = Array("子丑寅卯辰巳午未申酉戌亥").map(String.init)
    private static let animals = Array("鼠牛虎兔龙蛇马羊猴鸡狗猪").map(String.init)
    private static let lunarMonths = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
    private static let lunarDays = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
    ]
}
