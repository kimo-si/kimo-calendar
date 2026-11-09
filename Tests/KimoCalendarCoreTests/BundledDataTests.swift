import Foundation
import Testing

@testable import KimoCalendarCore

struct BundledDataTests {
    // 实际校验交付应用使用的全部离线数据，防止资源更新引入无效公告。
    @Test(arguments: [2025, 2026, 2027]) func bundledAnnouncementsAreValid(year: Int) throws {
        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = project.appending(path: "Sources/KimoCalendar/Resources/Holidays/\(year).json")
        let data = try JSONDecoder().decode(HolidayYear.self, from: Data(contentsOf: file)).validated(for: year)
        #expect(data.year == year)
        #expect(!data.days.isEmpty)
    }
}
