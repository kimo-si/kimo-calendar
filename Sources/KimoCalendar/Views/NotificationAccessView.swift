import SwiftUI

struct NotificationAccessView: View {
    @Bindable var store: TodoStore
    var compact = false
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !compact {
                HStack {
                    Text("待办提醒").font(.headline)
                    Spacer()
                    Text(permissionText).font(.caption).foregroundStyle(.secondary)
                }
                Text("按设定时间显示系统通知，可直接完成或延后10分钟。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if store.permission == .notDetermined {
                    Button("开启通知") { Task { await store.enableNotifications() } }
                }
                if store.permission == .allowed {
                    Button(store.isTestingNotification ? "正在测试…" : "测试提醒") { Task { await store.testNotification() } }
                        .disabled(store.isTestingNotification)
                    Button("重新安排提醒") { Task { await store.reconcile() } }
                }
                if let url = Self.settingsURL, store.permission != .unavailable {
                    Link("系统通知设置", destination: url)
                }
            }
            .font(.system(size: 11))
            if !compact, let message = store.errorMessage ?? store.notice {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var permissionText: String {
        switch store.permission {
        case .notDetermined: "尚未开启"
        case .allowed: "已允许"
        case .denied: "已关闭"
        case .unavailable: "请使用打包后的应用"
        }
    }
}
