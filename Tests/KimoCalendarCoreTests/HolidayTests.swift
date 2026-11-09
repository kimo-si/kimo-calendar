import Foundation
import Testing

@testable import KimoCalendarCore

struct HolidayTests {
    // 下一年公告可覆盖前一年年底安排，数据来源顺序不影响覆盖结果。
    @Test func newerAnnouncementOverridesCrossYearDate() {
        let date = "2026-12-31"
        let previous = year(2026, days: [HolidayDay(name: "旧安排", date: date, isOffDay: false)])
        let next = year(2027, days: [HolidayDay(name: "元旦", date: date, isOffDay: true)])
        let index = HolidayIndex(years: [next, previous])
        #expect(index.day(CivilDate(year: 2026, month: 12, day: 31))?.isOffDay == true)
        #expect(index.day(CivilDate(year: 2026, month: 12, day: 30)) == nil)
    }

    // 缺少公告的空年度不能被误认为已经正式发布。
    @Test func emptyYearIsUnpublished() {
        let empty = HolidayYear(year: 2028, papers: [], days: [])
        #expect(throws: HolidayError.unpublished) { try empty.validated(for: 2028) }
    }

    // 拒绝假冒来源、错误年份、不合法日期以及冲突的重复日期。
    @Test func invalidHolidayDataIsRejected() {
        let day = HolidayDay(name: "春节", date: "2026-02-17", isOffDay: true)
        let fake = HolidayYear(
            year: 2026, papers: URL(string: "https://gov.cn.example.com/fake").map { [$0] } ?? [], days: [day])
        #expect(throws: HolidayError.invalidData) { try fake.validated(for: 2026) }
        #expect(throws: HolidayError.invalidData) { try year(2026).validated(for: 2027) }
        #expect(throws: HolidayError.invalidData) { try year(2026, days: [day, day]).validated(for: 2026) }
        let invalid = HolidayDay(name: "春节", date: "2026-02-30", isOffDay: true)
        #expect(throws: HolidayError.invalidData) { try year(2026, days: [invalid]).validated(for: 2026) }
    }

    // 核对调休周末上班标记不会被当作休假。
    @Test func makeUpWorkDayStaysWorking() {
        let workday = HolidayDay(name: "春节", date: "2026-02-14", isOffDay: false)
        let index = HolidayIndex(years: [year(2026, days: [workday])])
        #expect(index.day(CivilDate(year: 2026, month: 2, day: 14))?.isOffDay == false)
    }

    // 同步成功后可由另一个仓库实例从磁盘恢复，且二十四小时内不再联网。
    @Test func successfulSyncPersistsAndThrottles() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let transport = StubTransport(data: try JSONEncoder().encode(year(2026)))
        let repository = HolidayRepository(bundleDirectory: nil, cacheDirectory: folder, transport: transport)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = await repository.refresh(year: 2026, now: now)
        #expect(first.source == .network)
        #expect(first.error == nil)
        _ = await repository.refresh(year: 2026, now: now.addingTimeInterval(60))
        #expect(await transport.calls == 1)
        let restored = HolidayRepository(bundleDirectory: nil, cacheDirectory: folder, transport: transport)
        let cached = await restored.local(year: 2026)
        #expect(cached.source == .cache)
        #expect(cached.checkedAt == now)
        _ = await restored.refresh(year: 2026, now: now.addingTimeInterval(120))
        #expect(await transport.calls == 1)
        _ = await restored.refresh(year: 2026, force: true, now: now.addingTimeInterval(180))
        #expect(await transport.calls == 2)
    }

    // 损坏的磁盘副本降级到内置数据，网络失败也不清空可用安排。
    @Test func corruptCacheAndNetworkFailurePreserveBundledData() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundled = folder.appending(path: "bundle")
        let cache = folder.appending(path: "cache")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try JSONEncoder().encode(year(2026)).write(to: bundled.appending(path: "2026.json"))
        try Data("broken".utf8).write(to: cache.appending(path: "2026.json"))
        let transport = StubTransport(error: .network)
        let repository = HolidayRepository(bundleDirectory: bundled, cacheDirectory: cache, transport: transport)
        let result = await repository.refresh(year: 2026)
        #expect(result.source == .bundled)
        #expect(result.data?.days.count == 1)
        #expect(result.error == .network)
        _ = await repository.refresh(year: 2026)
        #expect(await transport.calls == 1)
    }

    // 网络返回空公告时不覆盖之前已成功保存的年度安排。
    @Test func unpublishedResponseDoesNotOverwriteCache() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let transport = StubTransport(data: try JSONEncoder().encode(year(2026)))
        let repository = HolidayRepository(bundleDirectory: nil, cacheDirectory: folder, transport: transport)
        _ = await repository.refresh(year: 2026)
        await transport.replace(with: try JSONEncoder().encode(HolidayYear(year: 2026, papers: [], days: [])))
        let result = await repository.refresh(year: 2026, force: true)
        #expect(result.data?.days.count == 1)
        #expect(result.error == .unpublished)
    }

    // 请求取消后允许立即重试，不把关闭面板当成一次失败的每日同步。
    @Test func cancelledRefreshCanRetryImmediately() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let transport = StubTransport(data: try JSONEncoder().encode(year(2026)))
        await transport.cancelNextRequest()
        let repository = HolidayRepository(bundleDirectory: nil, cacheDirectory: folder, transport: transport)
        let cancelled = await repository.refresh(year: 2026)
        #expect(cancelled.data == nil)
        #expect(cancelled.error == nil)
        let retry = await repository.refresh(year: 2026)
        #expect(retry.source == .network)
        #expect(await transport.calls == 2)
    }

    // 缓存写入失败不能冒充成功同步，也不能破坏已有离线副本。
    @Test func failedCacheWriteDoesNotReportSuccess() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let transport = StubTransport(data: try JSONEncoder().encode(year(2026)))
        let blocked = folder.appending(path: "file-not-directory")
        try Data().write(to: blocked)
        let repository = HolidayRepository(bundleDirectory: nil, cacheDirectory: blocked, transport: transport)
        let result = await repository.refresh(year: 2026)
        #expect(result.checkedAt == nil)
        #expect(result.source == .unavailable)
        #expect(result.error != nil)
    }

    // 构造明确包含正式公告地址的最小年度数据。
    private func year(_ value: Int, days: [HolidayDay]? = nil) -> HolidayYear {
        HolidayYear(
            year: value, papers: URL(string: "https://www.gov.cn/holiday").map { [$0] } ?? [],
            days: days ?? [HolidayDay(name: "元旦", date: "\(value)-01-01", isOffDay: true)])
    }

    // 为每个缓存测试创建独立目录，防止并行执行相互污染。
    private func temporaryDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "kimo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

private actor StubTransport: HolidayTransport {
    private var data: Data?
    private let error: HolidayError?
    private(set) var calls = 0
    private var shouldCancel = false

    // 构造确定的成功响应或失败，所有测试均不访问外部网络。
    init(data: Data? = nil, error: HolidayError? = nil) {
        self.data = data
        self.error = error
    }

    // 记录访问次数以验证同步限流和手动刷新行为。
    func fetch(year: Int) async throws -> Data {
        calls += 1
        if shouldCancel {
            shouldCancel = false
            throw CancellationError()
        }
        if let error { throw error }
        return data ?? Data()
    }

    // 替换后续响应，用于验证坏数据不会覆盖成功缓存。
    func replace(with data: Data) { self.data = data }

    // 模拟一次取消，核对关闭面板不会导致下一次打开被限流一天。
    func cancelNextRequest() { shouldCancel = true }
}
