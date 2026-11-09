import Foundation
import KimoCalendarCore
import Observation

@MainActor @Observable
final class TodoEditorState {
    var title = ""
    var hasReminder = false
    var reminderTime: Date
    private(set) var editingID: UUID?
    private let day: CivilDate
    private let engine: CalendarEngine
    var isEditing: Bool { editingID != nil }

    // 新事项默认不提醒，时间预设为未来半小时或所选日期上午九点。
    init(day: CivilDate, engine: CalendarEngine = CalendarEngine(), now: Date = .now) {
        self.day = day
        self.engine = engine
        let base = engine.date(day)
        reminderTime =
            engine.civilDate(now) == day
            ? now.addingTimeInterval(30 * 60)
            : engine.gregorian.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base
    }

    // 编辑保留 UUID；已过期的提醒需要重新选择，避免无效时间阻止修改标题。
    func edit(_ item: TodoItem) {
        editingID = item.id
        title = item.title
        hasReminder = item.reminderAt.map { $0 > .now } ?? false
        if let reminderAt = item.reminderAt { reminderTime = reminderAt }
    }

    // 统一将选择的时分绑定到当前待办日期，并交给领域层再次校验。
    func draft() -> TodoMutation.Draft {
        let parts = engine.gregorian.dateComponents([.hour, .minute], from: reminderTime)
        let date = engine.gregorian.date(
            bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0,
            second: 0, of: engine.date(day))
        return TodoMutation.Draft(
            id: editingID ?? UUID(), title: title, day: day,
            reminderAt: hasReminder ? date : nil)
    }

    // 保存或取消编辑后清空输入，不影响所选日期的清单。
    func reset() {
        title = ""
        editingID = nil
        hasReminder = false
    }
}
