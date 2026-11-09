import SwiftUI

struct CalendarPanel: View {
    @Bindable var model: CalendarModel
    let onPinChange: (Bool) -> Void
    let onClose: () -> Void
    @State private var requestedPage = 0

    var body: some View {
        ZStack {
            PanelBackground()
            if model.showSettings {
                SettingsView(model: model)
            } else {
                calendarContent
            }
        }
        .frame(width: CalendarTheme.width, height: CalendarTheme.height)
        .preferredColorScheme(model.appearance.colorScheme)
        .environment(\.calendarPalette, model.style.palette)
        .tint(model.style.palette.accent)
        .task(id: "\(model.year)-\(model.automaticSync)") { await model.loadHolidays() }
        .task(id: model.monthPageID) { await model.loadTodos() }
        .onChange(of: model.isPinned) { _, value in onPinChange(value) }
        .onExitCommand(perform: onClose)
        .background(keyboardShortcuts)
    }

    private var calendarContent: some View {
        VStack(spacing: CalendarTheme.contentSpacing) {
            CalendarHeader(model: model, onTurn: turnMonth)
            MonthGrid(
                days: model.days, monthID: model.monthPageID, monthTitle: model.monthTitle,
                selectedID: model.visibleSelectedID, showLunar: model.showLunar,
                showHolidayMarks: model.showHolidayMarks,
                previousPage: model.previousPage, nextPage: model.nextPage, requestedPage: requestedPage,
                navigationResetToken: model.pagingResetToken,
                todos: model.todos, onSelect: model.select, onOpenTodos: model.openTodos,
                onTurn: model.turnMonth
            )
            .popover(item: $model.presentedTodoDay, arrowEdge: .trailing) { day in
                TodoDayPopover(
                    store: model.todos, day: day,
                    lunar: model.engine.lunarFullDate(model.engine.date(day))
                ) {
                    await model.loadTodos(on: day)
                }
                .id(day)
                .environment(\.calendarPalette, model.style.palette)
                .preferredColorScheme(model.appearance.colorScheme)
            }
            HStack(alignment: .top, spacing: 8) {
                DayDetailCard(model: model)
                UpcomingEventsCard(model: model)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, CalendarTheme.topInset)
        .padding(.bottom, CalendarTheme.bottomInset)
    }

    private var keyboardShortcuts: some View {
        Group {
            Button("上个月") { turnMonth(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("下个月") { turnMonth(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("回到今天", action: model.goToToday).keyboardShortcut("t", modifiers: .command)
        }
        .hidden()
        .disabled(model.presentedTodoDay != nil || model.showSettings || model.showMonthPicker)
        .accessibilityHidden(true)
    }

    // 只更换月份数据，横向动画限制在月份页面内，避免日期按行上下重排。
    private func turnMonth(_ offset: Int) {
        requestedPage += offset
    }
}
