import Foundation

public struct HolidayDay: Codable, Equatable, Sendable {
    public let name: String
    public let date: String
    public let isOffDay: Bool

    // 保留数据源明确给出的休息日或调休上班日。
    public init(name: String, date: String, isOffDay: Bool) {
        self.name = name
        self.date = date
        self.isOffDay = isOffDay
    }
}
