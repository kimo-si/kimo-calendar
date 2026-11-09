import Foundation

public struct FestivalCalendar: Sendable {
    private let engine: CalendarEngine

    // 复用统一的公农历计算器，避免重复创建格式化器。
    public init(engine: CalendarEngine) { self.engine = engine }

    // 识别公历节日、非闰月传统节日，以及农历岁末除夕。
    public func festival(on date: Date) -> CalendarEvent? {
        let civil = engine.civilDate(date)
        let lunar = engine.chinese.dateComponents([.month, .day, .isLeapMonth], from: date)
        let solarName = Self.solarFestivals.first { $0.month == civil.month && $0.day == civil.day }?.name
        var lunarName: String?
        if lunar.isLeapMonth != true {
            lunarName = Self.lunarFestivals.first { $0.month == lunar.month && $0.day == lunar.day }?.name
        }
        let name = isNewYearsEve(date) ? "除夕" : (lunarName ?? solarName)
        return name.map { CalendarEvent(date: civil, name: $0, kind: .festival) }
    }

    // 扫描有限的未来一年并合并节气，用于最近节日列表。
    public func upcoming(from date: Date, limit: Int = 4) -> [CalendarEvent] {
        let start = engine.civilDate(date)
        let terms = SolarTermCalculator(engine: engine)
        let solarEvents = terms.events(year: start.year) + terms.events(year: start.year + 1)
        let festivals = (0..<370).compactMap { offset -> CalendarEvent? in
            guard let day = engine.gregorian.date(byAdding: .day, value: offset, to: date) else { return nil }
            return festival(on: day)
        }
        return Array(
            (festivals + solarEvents).filter { $0.date >= start }
                .sorted { $0.date == $1.date ? $0.name < $1.name : $0.date < $1.date }.prefix(limit))
    }

    // 通过次日是否正月初一判断除夕，兼容大小月与公历跨年。
    private func isNewYearsEve(_ date: Date) -> Bool {
        guard let next = engine.gregorian.date(byAdding: .day, value: 1, to: date) else { return false }
        let parts = engine.chinese.dateComponents([.month, .day, .isLeapMonth], from: next)
        return parts.month == 1 && parts.day == 1 && parts.isLeapMonth != true
    }

    private struct Rule: Sendable {
        let month: Int
        let day: Int
        let name: String
    }

    private static let solarFestivals: [Rule] = [
        Rule(month: 1, day: 1, name: "元旦"), Rule(month: 5, day: 1, name: "劳动节"),
        Rule(month: 10, day: 1, name: "国庆节"),
    ]
    private static let lunarFestivals: [Rule] = [
        Rule(month: 1, day: 1, name: "春节"), Rule(month: 1, day: 15, name: "元宵节"),
        Rule(month: 2, day: 2, name: "龙抬头"), Rule(month: 5, day: 5, name: "端午节"),
        Rule(month: 7, day: 7, name: "七夕"), Rule(month: 7, day: 15, name: "中元节"),
        Rule(month: 8, day: 15, name: "中秋节"), Rule(month: 9, day: 9, name: "重阳节"),
        Rule(month: 12, day: 8, name: "腊八节"), Rule(month: 12, day: 23, name: "小年"),
    ]
}
