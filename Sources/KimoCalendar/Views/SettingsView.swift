import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var model: CalendarModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var manualSyncTask: Task<Void, Never>?
    @Environment(\.calendarPalette) private var palette
    private static let repositoryURL = URL(string: "https://github.com/NateScarlet/holiday-cn")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ThemePickerView(style: $model.style)
                    displaySettings
                    Divider()
                    synchronization
                    Divider()
                    NotificationAccessView(store: model.todos)
                    Divider()
                    Toggle("登录时启动", isOn: $launchAtLogin).onChange(of: launchAtLogin, setLaunchAtLogin)
                    if let message = model.applicationMessage {
                        Text(message).font(.caption).foregroundStyle(palette.holiday)
                    }
                }
                .padding(.trailing, 2)
            }
            footer
        }
        .font(.system(size: 12))
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(20)
        .onDisappear { manualSyncTask?.cancel() }
    }

    private var displaySettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("外观", selection: $model.appearance) {
                ForEach(CalendarAppearance.allCases) { Text($0.title).tag($0) }
            }
            Toggle("显示农历", isOn: $model.showLunar)
            Toggle("显示放假「休」与调休「班」", isOn: $model.showHolidayMarks)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button("返回日历", systemImage: "chevron.left") { model.showSettings = false }
                .labelStyle(.iconOnly).buttonStyle(ToolbarButtonStyle())
            Text("设置").font(.system(size: 23, weight: .semibold))
            Spacer()
            Image(systemName: "calendar").font(.title2).foregroundStyle(palette.accent)
        }
    }

    private var synchronization: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("中国法定节假日").font(.headline)
            Toggle("自动检查放假与调休安排", isOn: $model.automaticSync)
            Text("打开日历时检查，每天最多一次。离线时继续使用本地数据。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(model.isSyncing ? "正在同步…" : "立即同步") {
                    manualSyncTask = Task { await model.loadHolidays(force: true) }
                }
                .disabled(model.isSyncing)
                if let date = model.relevantResult?.checkedAt {
                    Text(date, format: .dateTime.month().day().hour().minute()).foregroundStyle(.secondary)
                }
            }
            syncMessage
            HStack(spacing: 14) {
                if let source = model.sourceURL { Link("查看国务院公告", destination: source) }
                if let repository = Self.repositoryURL { Link("数据来源：holiday-cn", destination: repository) }
            }
            .font(.caption)
        }
    }

    @ViewBuilder private var syncMessage: some View {
        if let result = model.relevantResult, let error = result.error {
            Text(error == .unpublished ? "暂未获取到该年的正式安排；传统节日不代表放假。" : "更新未完成。已保留可用离线数据，可稍后重试。")
                .font(.caption).foregroundStyle(palette.holiday)
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            Text("Kimo 日历").fontWeight(.semibold)
            Spacer()
            Button("退出日历") { NSApplication.shared.terminate(nil) }
        }
    }

    // 登录项变更失败时恢复真实系统状态，并展示可操作的错误提示。
    private func setLaunchAtLogin(_ oldValue: Bool, _ newValue: Bool) {
        guard oldValue != newValue else { return }
        guard newValue != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            // 使用 macOS 管理的登录项，不写启动脚本或私有系统目录。
            if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            model.applicationMessage =
                SMAppService.mainApp.status == .requiresApproval
                ? "请在系统设置 → 通用 → 登录项中允许 Kimo 日历。" : nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            model.applicationMessage = "登录项设置失败，请将应用放入「应用程序」后重试。"
        }
    }
}
