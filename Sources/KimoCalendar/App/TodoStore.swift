import Foundation
import KimoCalendarCore
import Observation

@MainActor @Observable
final class TodoStore {
    private(set) var items: [TodoItem] = []
    private(set) var permission: TodoNotificationPermission = .notDetermined
    private(set) var scheduledIDs: Set<UUID> = []
    private(set) var isLoading = false
    private(set) var isTestingNotification = false
    private var pendingOperations = 0
    private var dayCounts: [CivilDate: Int] = [:]
    var errorMessage: String?
    var notice: String?
    var isSaving: Bool { pendingOperations > 0 }
    @ObservationIgnored private let coordinator: TodoCoordinator
    @ObservationIgnored private var currentQuery: TodoSnapshot.Query?
    @ObservationIgnored private var loadToken = UUID()
    @ObservationIgnored private var isReconciling = false

    // 构造轻量状态对象，数据库首次访问和所有写入均由后台 actor 完成。
    init(coordinator: TodoCoordinator? = nil) {
        let url = URL.applicationSupportDirectory.appending(path: "KimoCalendar/todos.sqlite3")
        self.coordinator =
            coordinator
            ?? TodoCoordinator(
                repository: SQLiteTodoRepository(url: url), notifications: MacTodoNotifications.make())
    }

    // 日期格子只查询聚合索引，不逐格读取磁盘。
    func unfinished(on day: CivilDate) -> Int { dayCounts[day] ?? 0 }

    // 以令牌丢弃旧日期的迟到响应，快速翻月不会显示错误日期的清单。
    func refresh(_ query: TodoSnapshot.Query) async {
        let token = UUID()
        loadToken = token
        if currentQuery?.day != query.day {
            items = []
            errorMessage = nil
            notice = nil
        }
        currentQuery = query
        isLoading = true
        defer { if loadToken == token { isLoading = false } }
        do {
            let state = try await coordinator.state(query)
            guard token == loadToken, !Task.isCancelled else { return }
            items = state.snapshot.items
            dayCounts = Dictionary(uniqueKeysWithValues: state.snapshot.counts.map { ($0.day, $0.unfinished) })
            permission = state.permission
            scheduledIDs = state.scheduledIDs
        } catch {
            guard token == loadToken, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    // UI 只传输领域命令；通知失败仍返回保存成功，避免用户重复创建待办。
    @discardableResult func perform(_ mutation: TodoMutation) async -> Bool {
        pendingOperations += 1
        errorMessage = nil
        defer { pendingOperations -= 1 }
        do {
            let result = try await coordinator.perform(mutation)
            notice = message(for: result.reminder)
            if let currentQuery { await refresh(currentQuery) }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // 唤醒、跨日和启动时校对系统提醒，没有后台高频计时器。
    func reconcile() async {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }
        do {
            let status = try await coordinator.reconcile()
            permission = await coordinator.permission()
            if status != .notNeeded { notice = message(for: status) }
            if let currentQuery { await refresh(currentQuery) }
        } catch { errorMessage = error.localizedDescription }
    }

    // 通知打开时按 UUID 查找，已经删除的事项不会被重建。
    func item(id: UUID) async -> TodoItem? {
        do { return try await coordinator.item(id: id) } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // 首次启用时请求授权，再恢复已保存的未来提醒。
    func enableNotifications() async {
        do {
            _ = try await coordinator.requestPermission()
            permission = await coordinator.permission()
            await reconcile()
        } catch { errorMessage = "未能开启系统通知，请稍后重试。" }
    }

    // 设置页显式发送一条测试提醒，不保存演示待办。
    func testNotification() async {
        guard permission == .allowed, !isTestingNotification else { return }
        isTestingNotification = true
        defer { isTestingNotification = false }
        do {
            try await MacTodoNotifications.sendTest()
            notice = "已安排测试提醒，将在 5 秒后显示。"
            // 只为用户主动测试等待一次，常规待办不启动轮询或常驻计时器。
            try await Task.sleep(for: .seconds(6))
            notice =
                await MacTodoNotifications.wasTestDelivered()
                ? "测试提醒已投递。如果没有看到横幅，请检查系统通知或专注模式设置。"
                : "系统已接收测试提醒，尚未确认显示。请检查系统通知设置。"
        } catch { errorMessage = "测试提醒安排失败，请检查系统通知设置。" }
    }

    // 显示与真实系统安排一致的提醒状态，过期提醒不会伪装成待投递。
    func reminderLabel(for item: TodoItem, now: Date = .now) -> String {
        guard let date = item.reminderAt else { return "不提醒" }
        let time = date.formatted(.dateTime.month().day().hour().minute())
        if item.isCompleted { return "已完成" }
        if date <= now { return "\(time) · 提醒时间已过" }
        if permission == .denied || permission == .notDetermined { return "\(time) · 通知未开启" }
        if scheduledIDs.contains(item.id) { return "\(time) 提醒" }
        return "\(time) · 提醒待安排"
    }

    // 通知状态与本地保存结果分开说明，失败信息不会丢失。
    private func message(for status: TodoReminderStatus) -> String? {
        switch status {
        case .notNeeded, .scheduled: nil
        case .permissionRequired: "待办已保存，通知尚未开启。可在设置中开启提醒。"
        case .unavailable: "待办已保存。请从打包后的 Kimo 日历应用启用提醒。"
        case .failed: "待办已保存，但提醒未安排成功。可在设置中重试。"
        }
    }
}
