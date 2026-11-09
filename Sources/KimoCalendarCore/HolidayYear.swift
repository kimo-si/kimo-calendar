import Foundation

public struct HolidayYear: Codable, Equatable, Sendable {
    public let year: Int
    public let papers: [URL]
    public let days: [HolidayDay]

    // 构造一年公告及其明确列出的放假、补班安排。
    public init(year: Int, papers: [URL], days: [HolidayDay]) {
        self.year = year
        self.papers = papers
        self.days = days
    }

    // 校验公告来源、年份、重复日期，防止无效响应覆盖本地有效数据。
    public func validated(for requestedYear: Int) throws -> Self {
        guard year == requestedYear else { throw HolidayError.invalidData }
        guard !papers.isEmpty, !days.isEmpty else { throw HolidayError.unpublished }
        guard papers.allSatisfy(Self.isOfficialPaper) else { throw HolidayError.invalidData }
        var dates = Set<CivilDate>()
        for day in days {
            guard let date = CivilDate(iso8601: day.date), !day.name.isEmpty,
                (year - 1...year + 1).contains(date.year), dates.insert(date).inserted
            else {
                throw HolidayError.invalidData
            }
        }
        return self
    }

    // 仅接受国务院网站及其子域名上的正式公告链接。
    private static func isOfficialPaper(_ url: URL) -> Bool {
        guard let host = url.host, ["https", "http"].contains(url.scheme ?? "") else { return false }
        return host == "gov.cn" || host.hasSuffix(".gov.cn")
    }
}

public enum HolidayError: Error, Equatable, Sendable {
    case unpublished
    case invalidData
    case network
}
