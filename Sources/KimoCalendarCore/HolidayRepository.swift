import Foundation

public actor HolidayRepository {
    public static let refreshInterval: TimeInterval = 24 * 60 * 60
    private static let memoryYearLimit = 5
    private let bundleDirectory: URL?
    private let cacheDirectory: URL
    private let transport: any HolidayTransport
    private var memory: [HolidayLoadResult] = []
    private var attempts: [(year: Int, date: Date)] = []

    // 将磁盘与 JSON 工作隔离在后台 actor，主线程只接收小型不可变结果。
    public init(bundleDirectory: URL?, cacheDirectory: URL, transport: any HolidayTransport = HTTPHolidayTransport()) {
        self.bundleDirectory = bundleDirectory
        self.cacheDirectory = cacheDirectory
        self.transport = transport
    }

    // 优先读取有效磁盘副本，其次读取应用自带副本，损坏缓存不会阻断启动。
    public func local(year: Int) -> HolidayLoadResult {
        if let result = memory.first(where: { $0.year == year }) { return result }
        let disk = readCache(year: year)
        let bundled = readBundled(year: year)
        let result = disk ?? bundled ?? HolidayLoadResult(year: year, data: nil, source: .unavailable)
        remember(result)
        return result
    }

    // 每年最多每天自动检查一次；手动刷新可跳过间隔，失败保留最后有效副本。
    public func refresh(year: Int, force: Bool = false, now: Date = .now) async -> HolidayLoadResult {
        let fallback = local(year: year)
        let lastAttempt = attempts.first { $0.year == year }?.date ?? fallback.checkedAt
        if !force, let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.refreshInterval { return fallback }
        do {
            // 下载后先校验再原子落盘，避免不完整网络响应破坏离线数据。
            let bytes = try await transport.fetch(year: year)
            try Task.checkCancellation()
            let data = try JSONDecoder().decode(HolidayYear.self, from: bytes).validated(for: year)
            try writeCache(data, checkedAt: now)
            recordAttempt(year: year, now: now)
            let result = HolidayLoadResult(year: year, data: data, source: .network, checkedAt: now)
            remember(result)
            return result
        } catch is CancellationError { return fallback } catch {
            recordAttempt(year: year, now: now)
            let result = HolidayLoadResult(
                year: year, data: fallback.data, source: fallback.source,
                checkedAt: fallback.checkedAt, error: (error as? HolidayError) ?? .network)
            remember(result)
            return result
        }
    }

    // 读取通过同样数据校验的缓存，同时保留真实成功同步时间。
    private func readCache(year: Int) -> HolidayLoadResult? {
        guard let bytes = try? Data(contentsOf: cacheURL(year)),
            let cache = try? JSONDecoder().decode(CacheEntry.self, from: bytes),
            let valid = try? cache.data.validated(for: year)
        else { return nil }
        return HolidayLoadResult(year: year, data: valid, source: .cache, checkedAt: cache.checkedAt)
    }

    // 只把带正式公告的内置文件视为已发布，空文件不冒充休假安排。
    private func readBundled(year: Int) -> HolidayLoadResult? {
        guard let url = bundleDirectory?.appending(path: "\(year).json"),
            let bytes = try? Data(contentsOf: url),
            let valid = try? JSONDecoder().decode(HolidayYear.self, from: bytes).validated(for: year)
        else { return nil }
        return HolidayLoadResult(year: year, data: valid, source: .bundled)
    }

    // 以原子替换写入年度缓存；失败向上返回，不能显示虚假的同步成功。
    private func writeCache(_ data: HolidayYear, checkedAt: Date) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let bytes = try JSONEncoder().encode(CacheEntry(data: data, checkedAt: checkedAt))
        try bytes.write(to: cacheURL(data.year), options: .atomic)
    }

    // 统一年度缓存文件路径。
    private func cacheURL(_ year: Int) -> URL { cacheDirectory.appending(path: "\(year).json") }

    // 维护有界年度缓存，连续浏览多年不会无限增加常驻内存。
    private func remember(_ result: HolidayLoadResult) {
        memory.removeAll { $0.year == result.year }
        memory.append(result)
        if memory.count > Self.memoryYearLimit { memory.removeFirst() }
    }

    // 记录成功或失败的尝试时间，离线期间反复打开面板也不会频繁重试。
    private func recordAttempt(year: Int, now: Date) {
        attempts.removeAll { $0.year == year }
        attempts.append((year, now))
        if attempts.count > Self.memoryYearLimit { attempts.removeFirst() }
    }

    private struct CacheEntry: Codable {
        let data: HolidayYear
        let checkedAt: Date
    }
}
