import KimoCalendarCore
import SwiftUI

struct TodoRow: View {
    let item: TodoItem
    let reminderLabel: String
    let isBusy: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(\.calendarPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button(
                item.isCompleted ? "恢复待办" : "完成待办",
                systemImage: item.isCompleted ? "checkmark.circle.fill" : "circle", action: onToggle
            )
            .labelStyle(.iconOnly).buttonStyle(.plain)
            .font(.system(size: 17)).foregroundStyle(item.isCompleted ? palette.accent : .secondary)
            .accessibilityLabel("\(item.isCompleted ? "恢复" : "完成")：\(item.title)")
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 12.5)).lineLimit(2)
                    .strikethrough(item.isCompleted).foregroundStyle(item.isCompleted ? .secondary : .primary)
                Text(reminderLabel).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("编辑待办", systemImage: "square.and.pencil", action: onEdit)
                .help("编辑：\(item.title)")
            Button("删除待办", systemImage: "trash", action: onDelete)
                .help("删除：\(item.title)")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .padding(.vertical, 10)
        .disabled(isBusy)
        .accessibilityElement(children: .contain)
    }
}
