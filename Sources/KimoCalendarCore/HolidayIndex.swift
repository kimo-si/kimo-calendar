import Foundation

public struct HolidayIndex: Sendable {
    // 日期键索引用于网格的 O(1) 查询，是按日期查询所必需的内部映射。
    private let dates: [CivilDate: HolidayDay]
    public let availableYears: Set<Int>

    // 按公告年份覆盖：下一年公告能覆盖上一年十二月的跨年调休。
    public init(years: [HolidayYear]) {
        var index: [CivilDate: HolidayDay] = [:]
        for year in years.sorted(by: { $0.year < $1.year }) {
            for day in year.days {
                guard let date = CivilDate(iso8601: day.date) else { continue }
                index[date] = day
            }
        }
        dates = index
        availableYears = Set(years.map(\.year))
    }

    // 返回公告明确规定的安排；未列出的日期不会被臆测为法定假期。
    public func day(_ date: CivilDate) -> HolidayDay? { dates[date] }
}
