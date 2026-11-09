import SwiftUI

struct TodoEditorView: View {
    @Bindable var editor: TodoEditorState
    let isSaving: Bool
    let onSave: () -> Void
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(editor.isEditing ? "编辑事项" : "添加事项")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if editor.isEditing {
                    Button("取消编辑", action: editor.reset).buttonStyle(.plain).font(.system(size: 11))
                }
            }
            TextField("例如：整理项目资料", text: $editor.title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .focused($isTitleFocused)
                .onSubmit(submit)
                .accessibilityLabel("待办标题")
            HStack {
                Toggle("到时提醒", isOn: $editor.hasReminder).toggleStyle(.checkbox)
                Spacer()
                DatePicker("提醒时间", selection: $editor.reminderTime, displayedComponents: .hourAndMinute)
                    .labelsHidden().disabled(!editor.hasReminder)
                    .accessibilityLabel("提醒时间")
            }
            .font(.system(size: 12))
            HStack {
                if isSaving {
                    ProgressView().controlSize(.small)
                    Text("正在保存…").foregroundStyle(.secondary)
                }
                Spacer()
                Button(editor.isEditing ? "保存修改" : "添加", action: onSave)
                    .buttonStyle(.borderedProminent).disabled(cannotSubmit)
            }
            .font(.system(size: 12))
        }
        .disabled(isSaving)
        .task { isTitleFocused = true }
    }

    private var cannotSubmit: Bool { isSaving || editor.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // 回车遵循与保存按钮相同的校验，避免提交空白事项。
    private func submit() { if !cannotSubmit { onSave() } }
}
