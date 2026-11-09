import KimoCalendarCore
import SwiftUI

struct TodoDayPopover: View {
    @Bindable var store: TodoStore
    let day: CivilDate
    let lunar: String
    let onLoad: () async -> Void
    @State private var editor: TodoEditorState
    @State private var pendingDeletion: TodoItem?
    @State private var showsDeleteConfirmation = false
    @State private var isSubmitting = false
    @Environment(\.calendarPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    // 每次打开日期时创建独立编辑状态，输入不会串到其他日期。
    init(store: TodoStore, day: CivilDate, lunar: String, onLoad: @escaping () async -> Void) {
        self.store = store
        self.day = day
        self.lunar = lunar
        self.onLoad = onLoad
        _editor = State(initialValue: TodoEditorState(day: day))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            heading
            Divider().opacity(0.6)
            todoList
            Divider().opacity(0.6)
            TodoEditorView(editor: editor, isSaving: store.isSaving || isSubmitting, onSave: save)
            statusMessage
        }
        .padding(17)
        .frame(width: 324)
        .background(PanelBackground())
        .tint(palette.accent)
        .task(id: day) { await onLoad() }
        .onExitCommand { dismiss() }
        .alert("删除这条待办？", isPresented: $showsDeleteConfirmation, presenting: pendingDeletion) { item in
            Button("删除", role: .destructive) {
                Task {
                    if await store.perform(.delete(id: item.id)), editor.editingID == item.id { editor.reset() }
                }
            }
            Button("取消", role: .cancel) {}
        } message: { item in
            Text("“\(item.title)”及其系统提醒将被删除。")
        }
    }

    private var heading: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(day.month)月\(day.day)日 · 待办").font(.system(size: 17, weight: .semibold))
                Text("农历 \(lunar) · \(store.unfinished(on: day)) 项未完成")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("关闭待办", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly).buttonStyle(ToolbarButtonStyle()).help("关闭待办（Esc）")
        }
    }

    private var todoList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if store.isLoading, store.items.isEmpty {
                    ProgressView().controlSize(.small).padding(15)
                } else if store.items.isEmpty {
                    Text("当天还没有待办，记下一件事吧。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 17)
                }
                ForEach(store.items) { item in
                    TodoRow(
                        item: item, reminderLabel: store.reminderLabel(for: item), isBusy: store.isSaving,
                        onToggle: {
                            Task { await store.perform(.completion(id: item.id, isCompleted: !item.isCompleted)) }
                        },
                        onEdit: { editor.edit(item) }, onDelete: { requestDeletion(item) })
                }
            }
        }
        .frame(height: min(205, max(51, Double(store.items.count) * 61)))
        .accessibilityLabel("\(day.month)月\(day.day)日的待办清单")
    }

    @ViewBuilder private var statusMessage: some View {
        if let error = store.errorMessage {
            Text(error).foregroundStyle(palette.holiday).font(.system(size: 11)).fixedSize(
                horizontal: false, vertical: true)
        } else if let notice = store.notice {
            Text(notice).foregroundStyle(.secondary).font(.system(size: 11)).fixedSize(
                horizontal: false, vertical: true)
        }
        if store.permission == .denied || store.permission == .notDetermined, store.notice != nil {
            NotificationAccessView(store: store, compact: true)
        }
    }

    // 保存成功后才清空编辑器；无效时间和磁盘错误保留用户输入。
    private func save() {
        guard !isSubmitting else { return }
        isSubmitting = true
        let draft = editor.draft()
        Task {
            defer { isSubmitting = false }
            if await store.perform(.save(draft)) { editor.reset() }
        }
    }

    // 用户确认后才执行删除事务，编辑状态与清单删除互不串用。
    private func requestDeletion(_ item: TodoItem) {
        pendingDeletion = item
        showsDeleteConfirmation = true
    }
}
