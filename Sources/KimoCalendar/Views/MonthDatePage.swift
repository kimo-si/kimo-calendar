import KimoCalendarCore
import SwiftUI

struct MonthDatePage: View {
    let days: [DayPresentation]
    let selectedID: CivilDate?
    let showLunar: Bool
    let showHolidayMarks: Bool
    let todos: TodoStore
    let onSelect: (DayPresentation) -> Void
    let onOpenTodos: (DayPresentation) -> Void
    @Environment(\.calendarPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: CalendarTheme.weekSpacing) {
            ForEach(days) { day in
                DayCell(
                    day: day, isSelected: day.date == selectedID,
                    showLunar: showLunar, showHolidayMarks: showHolidayMarks,
                    unfinishedTodos: todos.unfinished(on: day.date),
                    onSelect: { onSelect(day) }, onOpenTodos: { onOpenTodos(day) })
            }
        }
        .frame(height: CalendarTheme.monthRowsHeight)
        .background(scheme == .dark ? palette.darkSurface : palette.surface, in: .rect(cornerRadius: 8))
    }
}
