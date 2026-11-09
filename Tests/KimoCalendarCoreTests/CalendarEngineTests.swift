import Foundation
import Testing

@testable import KimoCalendarCore

struct CalendarEngineTests {
    private let engine = CalendarEngine(timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .gmt)

    // 检查周一起始、六周稳定布局及跨年补位。
    @Test func januaryGridCrossesYearCorrectly() {
        let dates = engine.monthDates(containing: date("2025-01-30"))
        #expect(dates.count == 42)
        #expect(engine.civilDate(dates[0]).iso8601 == "2024-12-30")
        #expect(engine.civilDate(dates[41]).iso8601 == "2025-02-09")
        #expect(engine.gregorian.component(.weekday, from: dates[0]) == 2)
    }

    // 检查周一恰好为月初时不会多补一整周。
    @Test func mondayMonthStartsAtFirst() {
        let dates = engine.monthDates(containing: date("2026-06-12"))
        #expect(engine.civilDate(dates[0]).iso8601 == "2026-06-01")
    }

    // 检查大小月夹取、闰年与可浏览年份边界。
    @Test func monthNavigationClampsAtLeapDay() {
        #expect(engine.moving(date("2024-01-31"), months: 1).map(engine.civilDate)?.iso8601 == "2024-02-29")
        #expect(engine.moving(date("2025-01-31"), months: 1).map(engine.civilDate)?.iso8601 == "2025-02-28")
        #expect(engine.moving(date("2099-12-01"), months: 1) == nil)
        #expect(engine.moving(date("1901-01-01"), months: -1) == nil)
    }

    // 核对真实春节日期，不复制参考图中公历与农历的日期偏差。
    @Test func lunarNewYearAndEveAreCorrect() {
        let festivals = FestivalCalendar(engine: engine)
        #expect(festivals.festival(on: date("2025-01-28"))?.name == "除夕")
        #expect(festivals.festival(on: date("2025-01-29"))?.name == "春节")
        #expect(engine.lunarFullDate(date("2025-01-30")) == "正月初二")
        #expect(festivals.festival(on: date("2026-02-17"))?.name == "春节")
    }

    // 检查闰月标记以及春节前生肖仍属于上一个农历年。
    @Test func lunarLeapMonthAndZodiac() {
        #expect(engine.lunarLabel(date("2025-07-25")) == "闰六月")
        #expect(engine.lunarYear(date("2025-01-28")).contains("生肖龙"))
        #expect(engine.lunarYear(date("2025-01-29")).contains("生肖蛇"))
    }

    // 检查跨夏令时的倒计时使用日历天而非固定二十四小时。
    @Test func dayDifferenceRespectsDaylightSaving() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let local = CalendarEngine(timeZone: zone)
        let start = local.date(CivilDate(year: 2026, month: 3, day: 7))
        let end = local.date(CivilDate(year: 2026, month: 3, day: 9))
        #expect(local.days(from: start, to: end) == 2)
    }

    // 校验二十四节气的数量、顺序和已知清明日期。
    @Test func solarTermsAreOrderedAndQingmingMatches() {
        let calculator = SolarTermCalculator(engine: engine)
        let terms = calculator.events(year: 2026)
        #expect(terms.count == 24)
        #expect(Set(terms.map(\.date)).count == 24)
        #expect(terms.map(\.date) == terms.map(\.date).sorted())
        #expect(terms.first { $0.name == "清明" }?.date.iso8601 == "2026-04-05")
        #expect(calculator.events(year: 2025).first { $0.name == "清明" }?.date.iso8601 == "2025-04-04")
        #expect(terms.first { $0.name == "冬至" }?.date.iso8601 == "2026-12-22")
    }

    // 验证未来节日从当天开始，且可以跨年得到下一年的元旦。
    @Test func upcomingEventsCrossYear() {
        let events = FestivalCalendar(engine: engine).upcoming(from: date("2026-12-31"))
        #expect(events.count == 4)
        #expect(events.first?.name == "元旦")
        #expect(events.first?.date.iso8601 == "2027-01-01")
    }

    // 检查日期解析拒绝无效日号和非规范格式。
    @Test func invalidCivilDatesAreRejected() {
        #expect(CivilDate(iso8601: "2025-02-29") == nil)
        #expect(CivilDate(iso8601: "2026-13-01") == nil)
        #expect(CivilDate(iso8601: "2026-1-01") == nil)
        #expect(CivilDate(iso8601: "2024-02-29") != nil)
    }

    // 为测试创建经过固定时区转换的已知日期。
    private func date(_ value: String) -> Date {
        engine.date(CivilDate(iso8601: value) ?? CivilDate(year: 2000, month: 1, day: 1))
    }
}
