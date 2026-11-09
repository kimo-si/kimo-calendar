import Foundation

public struct HolidayLoadResult: Equatable, Sendable {
    public enum Source: String, Sendable { case bundled, cache, network, unavailable }
    public let year: Int
    public let data: HolidayYear?
    public let source: Source
    public let checkedAt: Date?
    public let error: HolidayError?

    // 描述可用数据及同步结果；网络失败时仍携带离线数据。
    public init(year: Int, data: HolidayYear?, source: Source, checkedAt: Date? = nil, error: HolidayError? = nil) {
        self.year = year
        self.data = data
        self.source = source
        self.checkedAt = checkedAt
        self.error = error
    }
}
