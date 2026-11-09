import Foundation
import Testing

@testable import KimoCalendarCore

struct TodoCoordinatorTests {
    private let day = CivilDate(year: 2026, month: 11, day: 10)
    private let now = Date(timeIntervalSince1970: 1_794_225_600)

    // 只有用户保存第一条提醒时请求权限，之后使用稳定 ID 避免重复。
    @Test func firstReminderRequestsPermissionAndEditingReplacesIt() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let client = FakeTodoNotifications(permission: .notDetermined, grantsPermission: true)
        let coordinator = TodoCoordinator(repository: fixture.repository, notifications: client)
        let draft = TodoMutation.Draft(title: "首次提醒", day: day, reminderAt: now.addingTimeInterval(3600))
        #expect(try await coordinator.perform(.save(draft), now: now).reminder == .scheduled)
        _ = try await coordinator.perform(
            .save(
                .init(
                    id: draft.id, title: "修改提醒", day: day,
                    reminderAt: now.addingTimeInterval(7200))), now: now)
        #expect(await client.requests == 1)
        #expect(await client.scheduled.count == 1)
        #expect(await client.scheduled.first?.title == "修改提醒")
        #expect(await client.scheduled.first?.reminderAt == now.addingTimeInterval(7200))
    }

    // 拒绝系统权限时仍保存本地待办，并准确返回提醒未开启状态。
    @Test func deniedPermissionDoesNotLoseTask() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let client = FakeTodoNotifications(permission: .notDetermined, grantsPermission: false)
        let coordinator = TodoCoordinator(repository: fixture.repository, notifications: client)
        let draft = TodoMutation.Draft(title: "本地必须保留", day: day, reminderAt: now.addingTimeInterval(600))
        let result = try await coordinator.perform(.save(draft), now: now)
        #expect(result.reminder == .permissionRequired)
        #expect(try await fixture.repository.item(id: draft.id)?.title == draft.title)
        #expect(await client.scheduled.isEmpty)
    }

    // 系统添加通知失败后，不能报告安排成功或回滚数据库内容。
    @Test func schedulingFailureIsReportedSeparately() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let client = FakeTodoNotifications(permission: .allowed, failsScheduling: true)
        let coordinator = TodoCoordinator(repository: fixture.repository, notifications: client)
        let draft = TodoMutation.Draft(title: "保存成功，提醒失败", day: day, reminderAt: now.addingTimeInterval(600))
        #expect(try await coordinator.perform(.save(draft), now: now).reminder == .failed)
        #expect(try await fixture.repository.item(id: draft.id) != nil)
        #expect(await client.pendingIDs().isEmpty)
    }

    // 不带提醒的事项与启动恢复都不能主动弹通知权限对话框。
    @Test func plainTaskAndStartupNeverRequestPermission() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let client = FakeTodoNotifications(permission: .notDetermined, grantsPermission: true)
        let coordinator = TodoCoordinator(repository: fixture.repository, notifications: client)
        _ = try await coordinator.perform(.save(.init(title: "不提醒", day: day)), now: now)
        _ = try await fixture.repository.apply(
            .save(
                .init(
                    title: "等待授权", day: day,
                    reminderAt: now.addingTimeInterval(3600))), now: now)
        #expect(try await coordinator.reconcile(now: now) == .permissionRequired)
        #expect(await client.requests == 0)
    }

    // 完成与删除会移除系统提醒，恢复未来事项时只安排一条。
    @Test func completingAndDeletingCancelReminders() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let client = FakeTodoNotifications(permission: .allowed)
        let coordinator = TodoCoordinator(repository: fixture.repository, notifications: client)
        let draft = TodoMutation.Draft(title: "状态流转", day: day, reminderAt: now.addingTimeInterval(600))
        _ = try await coordinator.perform(.save(draft), now: now)
        _ = try await coordinator.perform(.completion(id: draft.id, isCompleted: true), now: now)
        #expect(await client.pendingIDs().isEmpty)
        _ = try await coordinator.perform(.completion(id: draft.id, isCompleted: false), now: now)
        #expect(await client.pendingIDs() == [draft.id])
        _ = try await coordinator.perform(.delete(id: draft.id), now: now)
        #expect(await client.pendingIDs().isEmpty)
    }

    // 启动对账移除孤立提醒，并且不会补发过期事项。
    @Test func reconciliationRemovesOrphansAndSkipsPastReminders() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let client = FakeTodoNotifications(permission: .allowed)
        let coordinator = TodoCoordinator(repository: fixture.repository, notifications: client)
        let past = TodoMutation.Draft(title: "已经过期", day: day, reminderAt: now.addingTimeInterval(-10))
        _ = try await fixture.repository.apply(.save(past), now: now.addingTimeInterval(-100))
        await client.seedOrphan()
        #expect(try await coordinator.reconcile(now: now) == .notNeeded)
        #expect(await client.pendingIDs().isEmpty)
    }

    // 唤醒时保留系统尚未投递的过期请求，不干扰 macOS 的睡眠恢复投递。
    @Test func wakingDoesNotCancelOverdueSystemRequest() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let client = FakeTodoNotifications(permission: .allowed)
        let coordinator = TodoCoordinator(repository: fixture.repository, notifications: client)
        let draft = TodoMutation.Draft(title: "睡眠期间到期", day: day, reminderAt: now.addingTimeInterval(-10))
        _ = try await fixture.repository.apply(.save(draft), now: now.addingTimeInterval(-100))
        let item = try #require(try await fixture.repository.item(id: draft.id))
        await client.seedPending(item)
        #expect(try await coordinator.reconcile(now: now) == .notNeeded)
        #expect(await client.pendingIDs() == [draft.id])
    }

    // 通知添加尚未返回时立即完成，完成操作必须在之后撤销旧提醒。
    @Test func concurrentCompletionCannotLeaveStaleNotification() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let client = FakeTodoNotifications(permission: .allowed, delaysScheduling: true)
        let coordinator = TodoCoordinator(repository: fixture.repository, notifications: client)
        let draft = TodoMutation.Draft(title: "并发完成", day: day, reminderAt: now.addingTimeInterval(600))
        let saving = Task { try await coordinator.perform(.save(draft), now: now) }
        await client.waitForScheduling()
        let completing = Task { try await coordinator.perform(.completion(id: draft.id, isCompleted: true), now: now) }
        _ = try await saving.value
        _ = try await completing.value
        #expect(await client.pendingIDs().isEmpty)
        #expect(try await fixture.repository.item(id: draft.id)?.isCompleted == true)
    }

    // 关闭浮窗取消外层等待，也不能中断已开始的数据库与通知一致性操作。
    @Test func cancellingCallerDoesNotInterruptCommittedOperation() async throws {
        let fixture = try TodoTestFixture()
        defer { fixture.cleanup() }
        let client = FakeTodoNotifications(permission: .allowed, delaysScheduling: true)
        let coordinator = TodoCoordinator(repository: fixture.repository, notifications: client)
        let draft = TodoMutation.Draft(title: "关闭浮窗仍保留", day: day, reminderAt: now.addingTimeInterval(600))
        let saving = Task { try await coordinator.perform(.save(draft), now: now) }
        await client.waitForScheduling()
        saving.cancel()
        _ = try await saving.value
        #expect(try await fixture.repository.item(id: draft.id) != nil)
        #expect(await client.pendingIDs() == [draft.id])
    }
}

private actor FakeTodoNotifications: TodoNotificationClient {
    private var authorization: TodoNotificationPermission
    private let grantsPermission: Bool
    private let failsScheduling: Bool
    private let delaysScheduling: Bool
    private var waiting: CheckedContinuation<Void, Never>?
    private var startedScheduling = false
    private(set) var requests = 0
    private(set) var scheduled: [TodoItem] = []

    // 为协调层提供可控权限、失败和时序，不访问真实通知中心。
    init(
        permission: TodoNotificationPermission, grantsPermission: Bool = true,
        failsScheduling: Bool = false, delaysScheduling: Bool = false
    ) {
        authorization = permission
        self.grantsPermission = grantsPermission
        self.failsScheduling = failsScheduling
        self.delaysScheduling = delaysScheduling
    }

    // 返回模拟的当前系统授权状态。
    func permission() async -> TodoNotificationPermission { authorization }

    // 记录是否发生越权或重复的主动授权请求。
    func requestPermission() async throws -> Bool {
        requests += 1
        authorization = grantsPermission ? .allowed : .denied
        return grantsPermission
    }

    // 返回稳定 ID 集合，供通知去重和取消断言使用。
    func pendingIDs() async -> Set<UUID> { Set(scheduled.map(\.id)) }

    // 可暂停一次通知写入，以复现保存和完成同时发生的竞态。
    func schedule(_ item: TodoItem) async throws {
        startedScheduling = true
        waiting?.resume()
        waiting = nil
        if delaysScheduling { try await Task.sleep(for: .milliseconds(35)) }
        if failsScheduling { throw TodoError.database(-1) }
        scheduled.removeAll { $0.id == item.id }
        scheduled.append(item)
    }

    // 模拟系统取消同一 ID 的待投递通知。
    func cancel(_ ids: Set<UUID>) async { scheduled.removeAll { ids.contains($0.id) } }

    // 插入数据库不存在的通知，验证启动恢复会清理它。
    func seedOrphan() {
        scheduled.append(
            TodoItem(
                id: UUID(), title: "孤立提醒", day: .init(year: 2026, month: 11, day: 1),
                reminderAt: .distantFuture, isCompleted: false, createdAt: .now, updatedAt: .now))
    }

    // 模拟 macOS 在睡眠中尚未投递的已安排请求。
    func seedPending(_ item: TodoItem) { scheduled.append(item) }

    // 用 continuation 等待明确时序，测试不依赖不确定的固定长延时。
    func waitForScheduling() async {
        if startedScheduling { return }
        await withCheckedContinuation { waiting = $0 }
    }
}
