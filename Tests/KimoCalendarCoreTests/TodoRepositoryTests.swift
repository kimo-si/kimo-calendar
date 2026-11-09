import Foundation
import Testing

@testable import KimoCalendarCore

struct TodoRepositoryTests {
    private let day = CivilDate(year: 2026, month: 11, day: 10)
    private let now = Date(timeIntervalSince1970: 1_794_225_600)

    // 待办提交后由第二个连接读取，验证真实磁盘持久化及参数化文本。
    @Test func persistsAcrossRepositoryInstances() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let title = "  会议'); DROP TABLE todos; --  "
        let draft = TodoMutation.Draft(title: title, day: day)
        _ = try await fixture.repository.apply(.save(draft), now: now)
        let reopened = SQLiteTodoRepository(url: fixture.url)
        let saved = try #require(try await reopened.item(id: draft.id))
        #expect(saved.title == title.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(saved.day == day)
        let snapshot = try await reopened.snapshot(query(day))
        #expect(snapshot.items.count == 1)
        #expect(snapshot.counts.first?.unfinished == 1)
    }

    // 跨日期编辑保留 UUID、创建时间及完成状态，不在原日期留下副本。
    @Test func editingMovesWithoutDuplicating() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let draft = TodoMutation.Draft(title: "原事项", day: day)
        _ = try await fixture.repository.apply(.save(draft), now: now)
        _ = try await fixture.repository.apply(.completion(id: draft.id, isCompleted: true), now: now)
        let next = CivilDate(year: 2026, month: 11, day: 11)
        _ = try await fixture.repository.apply(
            .save(.init(id: draft.id, title: "修改事项", day: next)), now: now.addingTimeInterval(60))
        let saved = try #require(try await fixture.repository.item(id: draft.id))
        #expect(saved.createdAt == now)
        #expect(saved.isCompleted)
        #expect(saved.title == "修改事项")
        #expect(try await fixture.repository.snapshot(query(day)).items.isEmpty)
        #expect(try await fixture.repository.snapshot(query(next)).items.count == 1)
    }

    // 完成与恢复只更改状态，日期圆点计数同步变化而原事项仍保留。
    @Test func completionAndRestorationUpdateCounts() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let draft = TodoMutation.Draft(title: "提交材料", day: day)
        _ = try await fixture.repository.apply(.save(draft), now: now)
        _ = try await fixture.repository.apply(.completion(id: draft.id, isCompleted: true), now: now)
        let completed = try await fixture.repository.snapshot(query(day))
        #expect(completed.items.count == 1)
        #expect(completed.counts.isEmpty)
        _ = try await fixture.repository.apply(.completion(id: draft.id, isCompleted: false), now: now)
        #expect(try await fixture.repository.snapshot(query(day)).counts.first?.unfinished == 1)
    }

    // 删除是幂等的，重复的系统动作不会导致错误或重新创建待办。
    @Test func deletionIsIdempotent() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let draft = TodoMutation.Draft(title: "删除测试", day: day)
        _ = try await fixture.repository.apply(.save(draft), now: now)
        _ = try await fixture.repository.apply(.delete(id: draft.id), now: now)
        _ = try await fixture.repository.apply(.delete(id: draft.id), now: now)
        #expect(try await fixture.repository.item(id: draft.id) == nil)
        #expect(try await fixture.repository.snapshot(query(day)).counts.isEmpty)
    }

    // 无效编辑在事务内失败后，之前已保存的标题保持不变。
    @Test func invalidChangesPreserveExistingData() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let draft = TodoMutation.Draft(title: "保留原内容", day: day)
        _ = try await fixture.repository.apply(.save(draft), now: now)
        await #expect(throws: TodoError.invalidTitle) {
            try await fixture.repository.apply(.save(.init(id: draft.id, title: "  ", day: day)), now: now)
        }
        await #expect(throws: TodoError.pastReminder) {
            try await fixture.repository.apply(
                .save(.init(id: draft.id, title: "错误时间", day: day, reminderAt: now)), now: now)
        }
        #expect(try await fixture.repository.item(id: draft.id)?.title == "保留原内容")
    }

    // 校验日期和文本边界，避免 SQLite 自动接受不合法日期或截断 NUL 标题。
    @Test func draftValidationRejectsInvalidValues() {
        #expect(throws: TodoError.invalidDate) {
            try TodoMutation.Draft(title: "日期", day: CivilDate(year: 2026, month: 2, day: 30)).validated(now: now)
        }
        #expect(throws: TodoError.invalidTitle) {
            try TodoMutation.Draft(title: "内容\0截断", day: day).validated(now: now)
        }
        #expect(throws: TodoError.invalidTitle) {
            try TodoMutation.Draft(title: String(repeating: "字", count: 201), day: day).validated(now: now)
        }
    }

    // 已完成事项收到旧通知的延后操作时，不得重新变成未完成。
    @Test func snoozingCannotReviveCompletedItem() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let draft = TodoMutation.Draft(title: "稍后提醒", day: day, reminderAt: now.addingTimeInterval(100))
        _ = try await fixture.repository.apply(.save(draft), now: now)
        _ = try await fixture.repository.apply(.snooze(id: draft.id, until: now.addingTimeInterval(600)), now: now)
        #expect(try await fixture.repository.item(id: draft.id)?.reminderAt == now.addingTimeInterval(600))
        _ = try await fixture.repository.apply(.completion(id: draft.id, isCompleted: true), now: now)
        _ = try await fixture.repository.apply(.snooze(id: draft.id, until: now.addingTimeInterval(900)), now: now)
        #expect(try await fixture.repository.item(id: draft.id)?.isCompleted == true)
        #expect(try await fixture.repository.upcomingReminders(after: now).isEmpty)
    }

    // 并发请求经过单一存储 actor 和事务，不丢写入、不产生重复标识。
    @Test func concurrentWritesAreDurable() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<24 {
                group.addTask {
                    _ = try await fixture.repository.apply(.save(.init(title: "事项\(index)", day: day)), now: now)
                }
            }
            try await group.waitForAll()
        }
        let snapshot = try await fixture.repository.snapshot(query(day))
        #expect(snapshot.items.count == 24)
        #expect(Set(snapshot.items.map(\.id)).count == 24)
        #expect(snapshot.counts.first?.unfinished == 24)
    }

    // 事务第二条 SQL 失败时，第一条成功写入也必须被回滚。
    @Test func transactionRollsBackEarlierStatements() throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let db = try SQLiteDatabase(url: fixture.url)
        try db.execute("CREATE TABLE rollback_test (value INTEGER CHECK(value > 0))")
        #expect(throws: (any Error).self) {
            try db.transaction(.write) {
                try db.execute("INSERT INTO rollback_test VALUES (?)", values: [.integer(1)])
                try db.execute("INSERT INTO rollback_test VALUES (?)", values: [.integer(-1)])
            }
        }
        #expect(try db.query("SELECT value FROM rollback_test") { $0.number(0) }.isEmpty)
    }

    // 用于验证当天清单与覆盖整个十一月的日期标记。
    private func query(_ day: CivilDate) -> TodoSnapshot.Query {
        .init(
            day: day, firstDay: CivilDate(year: 2026, month: 11, day: 1),
            lastDay: CivilDate(year: 2026, month: 11, day: 30))
    }
}

struct TodoTestFixture: Sendable {
    let directory: URL
    let url: URL
    let repository: SQLiteTodoRepository

    // 每个用例使用独立真实数据库，不会接触用户的待办文件。
    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "kimo-todo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "todos.sqlite3")
        repository = SQLiteTodoRepository(url: url)
    }

    // 测试结束后删除本用例创建的临时目录。
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
