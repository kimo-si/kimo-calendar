import Foundation

public protocol HolidayTransport: Sendable {
    // 下载指定年份的公告数据，允许测试替换真实网络。
    func fetch(year: Int) async throws -> Data
}

public struct HTTPHolidayTransport: HolidayTransport {
    private static let endpoints = [
        "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/",
        "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/",
    ]
    private let session: URLSession
    private static let maximumResponseBytes = 256 * 1024

    // 使用无持久缓存、无 Cookie 的轻量网络会话。
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    // 主站失败时尝试镜像；取消请求时立即退出，不继续重试。
    public func fetch(year: Int) async throws -> Data {
        var failure: HolidayError = .network
        for endpoint in Self.endpoints {
            try Task.checkCancellation()
            do { return try await download(endpoint: endpoint, year: year) } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                failure = (error as? HolidayError) ?? .network
            }
        }
        throw failure
    }

    // 限制响应体大小并在切换镜像前验证 JSON，避免缓存错误页面。
    private func download(endpoint: String, year: Int) async throws -> Data {
        guard let url = URL(string: endpoint + "\(year).json") else { throw HolidayError.invalidData }
        let (stream, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse else { throw HolidayError.network }
        guard http.statusCode != 404 else { throw HolidayError.unpublished }
        guard http.statusCode == 200 else { throw HolidayError.network }
        guard response.expectedContentLength <= Self.maximumResponseBytes else { throw HolidayError.invalidData }
        var data = Data()
        for try await byte in stream {
            guard data.count < Self.maximumResponseBytes else { throw HolidayError.invalidData }
            data.append(byte)
        }
        _ = try JSONDecoder().decode(HolidayYear.self, from: data).validated(for: year)
        return data
    }
}
