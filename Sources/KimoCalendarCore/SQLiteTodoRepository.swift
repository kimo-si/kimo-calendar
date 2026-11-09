import Foundation

public actor SQLiteTodoRepository: TodoRepository {
    private let url: URL
    private var database: SQLiteDatabase?
    private static let columns = "id, title, day, reminder, completed, created_at, updated_at"

    // 只保存路径，延迟到后台 actor 的首次访问才打开 SQLite。
    public init(url: URL) { self.url = url }

    // 所有写操作在一个立即事务中完成，出错时由数据库层回滚。
    public func apply(_ mutation: TodoMutation, now: Date) throws -> TodoChange {
        let db = try connection()
        return try db.transaction(.write) {
            switch mutation {
            case .save(let draft): return .saved(try save(draft.validated(now: now), now: now, db: db))
            case .completion(let id, let completed): return .saved(try complete(id, value: completed, now: now, db: db))
            case .snooze(let id, let until): return .saved(try snooze(id, until: until, now: now, db: db))
            case .delete(let id):
                try db.execute("DELETE FROM todos WHERE id = ?", values: [.text(id.uuidString)])
                return .deleted(id)
            }
        }
    }

    // 列表和日期计数共享同一读取事务，避免标记和清单状态不一致。
    public func snapshot(_ query: TodoSnapshot.Query) throws -> TodoSnapshot {
        let db = try connection()
        return try db.transaction(.read) {
            let items = try db.query(
                "SELECT \(Self.columns) FROM todos WHERE day = ? ORDER BY completed, reminder IS NULL, reminder, created_at",
                values: [.text(query.day.iso8601)], map: decode)
            let counts = try db.query(
                "SELECT day, COUNT(*) FROM todos WHERE day >= ? AND day <= ? AND completed = 0 GROUP BY day",
                values: [.text(query.firstDay.iso8601), .text(query.lastDay.iso8601)], map: decodeCount)
            return TodoSnapshot(items: items, counts: counts)
        }
    }

    // 按稳定标识查找通知对应的待办。
    public func item(id: UUID) throws -> TodoItem? { try find(id, db: connection()) }

    // 系统提醒恢复只读取尚未完成的未来事项，不扫描 UI 或定时轮询。
    public func upcomingReminders(after date: Date) throws -> [TodoItem] {
        try connection().query(
            "SELECT \(Self.columns) FROM todos WHERE completed = 0 AND reminder > ? ORDER BY reminder",
            values: [.real(date.timeIntervalSince1970)], map: decode)
    }

    // 一次聚合查询返回有效提醒标识，唤醒校对不逐条查询数据库。
    public func activeReminderIDs() throws -> Set<UUID> {
        Set(
            try connection().query("SELECT id FROM todos WHERE completed = 0 AND reminder IS NOT NULL") { row in
                guard let text = row.text(0), let id = UUID(uuidString: text) else { throw TodoError.database(11) }
                return id
            })
    }

    // 创建一次连接并检查数据版本，未知的新版本不能被静默覆盖。
    private func connection() throws -> SQLiteDatabase {
        if let database { return database }
        let db = try SQLiteDatabase(url: url)
        let version = try db.query("PRAGMA user_version") { Int($0.number(0) ?? 0) }.first ?? 0
        guard version <= 1 else { throw TodoError.unsupportedSchema }
        if version == 0 { try createSchema(db) }
        database = db
        return db
    }

    // 将建表、索引和版本号在同一事务中提交，首次启动中断也可安全重试。
    private func createSchema(_ db: SQLiteDatabase) throws {
        try db.transaction(.write) {
            try db.execute(
                """
                CREATE TABLE IF NOT EXISTS todos (
                    id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, day TEXT NOT NULL,
                    reminder REAL, completed INTEGER NOT NULL CHECK(completed IN (0, 1)),
                    created_at REAL NOT NULL, updated_at REAL NOT NULL
                )
                """)
            try db.execute("CREATE INDEX IF NOT EXISTS todos_day ON todos(day, completed)")
            try db.execute("CREATE INDEX IF NOT EXISTS todos_reminder ON todos(reminder) WHERE completed = 0")
            try db.execute("PRAGMA user_version=1")
        }
    }

    // 更新时保留创建时间与完成状态，修改日期后不会留下旧日期的副本。
    private func save(_ draft: TodoMutation.Draft, now: Date, db: SQLiteDatabase) throws -> TodoItem {
        let existing = try find(draft.id, db: db)
        let item = TodoItem(
            id: draft.id, title: draft.title, day: draft.day, reminderAt: draft.reminderAt,
            isCompleted: existing?.isCompleted ?? false, createdAt: existing?.createdAt ?? now, updatedAt: now)
        try persist(item, db: db)
        return item
    }

    // 完成操作保留原提醒时间供查看；提醒撤销在事务提交后执行。
    private func complete(_ id: UUID, value: Bool, now: Date, db: SQLiteDatabase) throws -> TodoItem {
        guard let old = try find(id, db: db) else { throw TodoError.missingItem }
        let item = TodoItem(
            id: old.id, title: old.title, day: old.day, reminderAt: old.reminderAt,
            isCompleted: value, createdAt: old.createdAt, updatedAt: now)
        try persist(item, db: db)
        return item
    }

    // 稍后提醒只更新未完成事项，已完成的通知操作不会复活待办。
    private func snooze(_ id: UUID, until: Date, now: Date, db: SQLiteDatabase) throws -> TodoItem {
        guard until > now else { throw TodoError.pastReminder }
        guard let old = try find(id, db: db) else { throw TodoError.missingItem }
        guard !old.isCompleted else { return old }
        let item = TodoItem(
            id: old.id, title: old.title, day: old.day, reminderAt: until,
            isCompleted: false, createdAt: old.createdAt, updatedAt: now)
        try persist(item, db: db)
        return item
    }

    // 集中参数化写入，所有变更沿用同一稳定 UUID。
    private func persist(_ item: TodoItem, db: SQLiteDatabase) throws {
        try db.execute(
            """
            INSERT INTO todos (\(Self.columns)) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET title=excluded.title, day=excluded.day,
                reminder=excluded.reminder, completed=excluded.completed, updated_at=excluded.updated_at
            """,
            values: [
                .text(item.id.uuidString), .text(item.title), .text(item.day.iso8601),
                item.reminderAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                .integer(item.isCompleted ? 1 : 0), .real(item.createdAt.timeIntervalSince1970),
                .real(item.updatedAt.timeIntervalSince1970),
            ])
    }

    // 根据主键读取一条记录，避免 UI 编辑时按标题或行号定位。
    private func find(_ id: UUID, db: SQLiteDatabase) throws -> TodoItem? {
        try db.query("SELECT \(Self.columns) FROM todos WHERE id = ?", values: [.text(id.uuidString)], map: decode)
            .first
    }

    // 拒绝损坏的关键字段，不构造虚假日期或随机标识来掩盖数据问题。
    private func decode(_ row: SQLiteDatabase.Statement) throws -> TodoItem {
        guard let rawID = row.text(0), let id = UUID(uuidString: rawID), let title = row.text(1),
            let rawDay = row.text(2), let day = CivilDate(iso8601: rawDay),
            let created = row.number(5), let updated = row.number(6)
        else { throw TodoError.database(11) }
        return TodoItem(
            id: id, title: title, day: day, reminderAt: row.number(3).map(Date.init(timeIntervalSince1970:)),
            isCompleted: row.number(4) == 1, createdAt: Date(timeIntervalSince1970: created),
            updatedAt: Date(timeIntervalSince1970: updated))
    }

    // 将 SQL 聚合结果转换为日期标记对象。
    private func decodeCount(_ row: SQLiteDatabase.Statement) throws -> TodoSnapshot.DayCount {
        guard let text = row.text(0), let day = CivilDate(iso8601: text) else { throw TodoError.database(11) }
        return TodoSnapshot.DayCount(day: day, unfinished: Int(row.number(1) ?? 0))
    }
}
