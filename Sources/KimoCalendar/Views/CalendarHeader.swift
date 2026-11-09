import SwiftUI

struct CalendarHeader: View {
    @Bindable var model: CalendarModel
    let onTurn: (Int) -> Void
    @Environment(\.calendarPalette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            Button("上个月", systemImage: "chevron.left") { onTurn(-1) }
                .disabled(!model.canGoBack)
                .help("上个月（←）")
            monthSelector
            Button("下个月", systemImage: "chevron.right") { onTurn(1) }
                .disabled(!model.canGoForward)
                .help("下个月（→）")
            Spacer(minLength: 4)
            todayButton
            Button(model.isPinned ? "取消置顶" : "保持打开", systemImage: model.isPinned ? "pin.fill" : "pin") {
                model.isPinned.toggle()
            }
            .foregroundStyle(model.isPinned ? palette.accent : .primary)
            .help(model.isPinned ? "取消固定面板" : "固定面板，点击其他地方时保持打开")
            Button("设置", systemImage: "gearshape") { model.showSettings = true }
                .help("设置")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(ToolbarButtonStyle())
        .frame(height: 44)
    }

    private var monthSelector: some View {
        Button {
            model.showMonthPicker.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(model.monthTitle).font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                Text(model.monthSubtitle).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择年月，当前\(model.monthTitle)")
        .popover(isPresented: $model.showMonthPicker, arrowEdge: .bottom) {
            MonthPickerView(model: model).environment(\.calendarPalette, palette)
        }
    }

    private var todayButton: some View {
        Button(action: model.goToToday) {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text("今天")
            }
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(.white.opacity(0.18), in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.09)))
        }
        .buttonStyle(.plain)
        .help("回到今天（⌘T）")
    }
}
