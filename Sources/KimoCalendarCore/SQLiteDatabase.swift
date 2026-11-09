import Foundation
import SQLite3

// SQLite 使用 FULLMUTEX，所有调用再由唯一存储 actor 串行执行；允许安全关闭句柄。
final class SQLiteDatabase: @unchecked Sendable {
    enum Value {
        case text(String)
        case real(Double)
        case integer(Int)
        case null
    }
    enum Transaction { case read, write }
    private let handle: OpaquePointer

    // 创建数据库连接，配置 WAL 与完整提交，不在主线程初始化磁盘状态。
    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var pointer: OpaquePointer?
        let code = sqlite3_open_v2(
            url.path, &pointer, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK, let pointer else {
            if let pointer { sqlite3_close_v2(pointer) }
            throw TodoError.database(code)
        }
        handle = pointer
        sqlite3_busy_timeout(handle, 3_000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
    }

    // SQLite 自身协调关闭，不遗留未释放的文件句柄。
    deinit { sqlite3_close_v2(handle) }

    // 统一事务边界，提交失败也显式回滚，防止留下半次修改。
    func transaction<T>(_ kind: Transaction, operation: () throws -> T) throws -> T {
        try execute(kind == .write ? "BEGIN IMMEDIATE" : "BEGIN DEFERRED")
        do {
            let result = try operation()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    // 执行参数化写入及数据库配置，语句由局部对象自动释放。
    func execute(_ sql: String, values: [Value] = []) throws {
        let statement = try Statement(database: handle, sql: sql, values: values)
        var code = sqlite3_step(statement.handle)
        while code == SQLITE_ROW { code = sqlite3_step(statement.handle) }
        guard code == SQLITE_DONE else { throw TodoError.database(code) }
    }

    // 将每行转换为指定值对象，不向外暴露 SQLite 指针。
    func query<T>(_ sql: String, values: [Value] = [], map: (Statement) throws -> T) throws -> [T] {
        let statement = try Statement(database: handle, sql: sql, values: values)
        var rows: [T] = []
        var code = sqlite3_step(statement.handle)
        while code == SQLITE_ROW {
            rows.append(try map(statement))
            code = sqlite3_step(statement.handle)
        }
        guard code == SQLITE_DONE else { throw TodoError.database(code) }
        return rows
    }

    final class Statement {
        let handle: OpaquePointer

        // 在准备完成后绑定值，文本按 SQLite TRANSIENT 规则复制，避免悬空指针。
        init(database: OpaquePointer, sql: String, values: [Value]) throws {
            var pointer: OpaquePointer?
            let code = sqlite3_prepare_v2(database, sql, -1, &pointer, nil)
            guard code == SQLITE_OK, let pointer else { throw TodoError.database(code) }
            handle = pointer
            for (index, value) in values.enumerated() { try bind(value, at: Int32(index + 1)) }
        }

        // 查询与写入退出作用域时释放编译后的语句。
        deinit { sqlite3_finalize(handle) }

        // 根据列的 NULL 状态读取字符串。
        func text(_ column: Int32) -> String? {
            sqlite3_column_text(handle, column).map { String(cString: $0) }
        }

        // 保留可空日期的 NULL 语义，不把空提醒变成 1970 年。
        func number(_ column: Int32) -> Double? {
            sqlite3_column_type(handle, column) == SQLITE_NULL ? nil : sqlite3_column_double(handle, column)
        }

        // 按值类型绑定参数，所有用户内容均不参与 SQL 拼接。
        private func bind(_ value: Value, at index: Int32) throws {
            let code: Int32
            switch value {
            case .text(let text):
                // -1 是 SQLite 定义的复制析构标记，不是可调用的真实函数地址。
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                code = text.withCString { sqlite3_bind_text(handle, index, $0, -1, transient) }
            case .real(let number): code = sqlite3_bind_double(handle, index, number)
            case .integer(let number): code = sqlite3_bind_int64(handle, index, Int64(number))
            case .null: code = sqlite3_bind_null(handle, index)
            }
            guard code == SQLITE_OK else { throw TodoError.database(code) }
        }
    }
}
