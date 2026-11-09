import Foundation

public struct CivilDate: Hashable, Comparable, Codable, Sendable, Identifiable {
    public let year: Int
    public let month: Int
    public let day: Int
    public var id: String { iso8601 }
    public var iso8601: String { "\(year)-\(Self.padded(month))-\(Self.padded(day))" }

    // 创建不受时区转换影响的公历日期值。
    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    // 严格解析并校验数据源中的 ISO 日期，拒绝自动进位的无效日期。
    public init?(iso8601: String) {
        let parts = iso8601.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, iso8601.count == 10 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
            calendar.component(.year, from: date) == year,
            calendar.component(.month, from: date) == month,
            calendar.component(.day, from: date) == day
        else { return nil }
    }

    // 按公历年月日排序，供节假日索引与即将到来的节日使用。
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // 为存储格式补齐月份与日期的两位数字。
    private static func padded(_ number: Int) -> String {
        number < 10 ? "0\(number)" : "\(number)"
    }
}
