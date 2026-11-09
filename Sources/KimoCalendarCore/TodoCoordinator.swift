import Foundation

public actor TodoCoordinator {
    public struct Result: Sendable {
        public let change: TodoChange
        public let reminder: TodoReminderStatus
    }

    public struct State: Sendable {
        public let snapshot: TodoSnapshot
        public let permission: TodoNotificationPermission
        public let scheduledIDs: Set<UUID>
    }

    private let repository: any TodoRepository
    private let notifications: any TodoNotificationClient
    private var operationTail: Task<Void, Never>?

    // 将持久化与系统通知分开注入，测试不会申请真实权限或发出通知。
    public init(repository: any TodoRepository, notifications: any TodoNotificationClient) {
        self.repository = repository
        self.notifications = notifications
    }

    // 串行执行事务提交及通知更新，关闭浮窗不会中断已经提交的用户操作。
    public func perform(_ mutation: TodoMutation, now: Date = .now) async throws -> Result {
        try await enqueue {
            // 数据库先完整提交，通知权限失败不能回滚用户已经保存的待办。
            let change = try await self.repository.apply(mutation, now: now)
            let status = await self.updateReminder(change, askPermission: Self.shouldAsk(mutation), now: now)
            return Result(change: change, reminder: status)
        }
    }

    // 返回本地快照与真实通知状态，未安排成功的提醒不会显示为已开启。
    public func state(_ query: TodoSnapshot.Query) async throws -> State {
        let snapshot = try await repository.snapshot(query)
        let permission = await notifications.permission()
        let ids = await notifications.pendingIDs()
        return State(snapshot: snapshot, permission: permission, scheduledIDs: ids)
    }

    // 通知点击需要定位日期时查询完整对象，不用通知正文作为数据源。
    public func item(id: UUID) async throws -> TodoItem? { try await repository.item(id: id) }

    // 设置页的明确操作可以主动请求通知权限。
    public func requestPermission() async throws -> Bool { try await notifications.requestPermission() }

    // 查询授权状态时不访问数据库，也不弹出系统权限对话框。
    public func permission() async -> TodoNotificationPermission { await notifications.permission() }

    // 启动和唤醒时恢复提醒意图，不申请权限，不补发已过期通知。
    public func reconcile(now: Date = .now) async throws -> TodoReminderStatus {
        try await enqueue {
            let items = try await self.repository.upcomingReminders(after: now)
            let desired = try await self.repository.activeReminderIDs()
            let pending = await self.notifications.pendingIDs()
            await self.notifications.cancel(pending.subtracting(desired))
            guard !items.isEmpty else { return .notNeeded }
            var result: TodoReminderStatus = .scheduled
            for item in items {
                let status = await self.updateReminder(.saved(item), askPermission: false, now: now)
                if status != .scheduled { result = status }
            }
            return result
        }
    }

    // 每个变更等待上一变更完成通知操作，避免快速编辑或完成后又安排旧提醒。
    private func enqueue<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = operationTail
        let task = Task {
            await previous?.value
            return try await operation()
        }
        operationTail = Task { _ = try? await task.value }
        return try await task.value
    }

    // 取消旧提醒后按最新持久化结果安排；通知失败只报告状态，不吞掉待办。
    private func updateReminder(_ change: TodoChange, askPermission: Bool, now: Date) async -> TodoReminderStatus {
        await notifications.cancel([change.id])
        guard case .saved(let item) = change, !item.isCompleted,
            let time = item.reminderAt, time > now
        else { return .notNeeded }
        var permission = await notifications.permission()
        if permission == .notDetermined, askPermission {
            do { _ = try await notifications.requestPermission() } catch { return .failed }
            permission = await notifications.permission()
        }
        if permission == .unavailable { return .unavailable }
        guard permission == .allowed else { return .permissionRequired }
        do {
            try await notifications.schedule(item)
            return .scheduled
        } catch { return .failed }
    }

    // 完成、删除和自动恢复不会触发通知权限弹窗。
    private static func shouldAsk(_ mutation: TodoMutation) -> Bool {
        switch mutation {
        case .save, .snooze: true
        case .completion, .delete: false
        }
    }
}
