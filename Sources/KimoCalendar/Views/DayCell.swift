import KimoCalendarCore
import SwiftUI

struct DayCell: View {
    let day: DayPresentation
    let isSelected: Bool
    let showLunar: Bool
    let showHolidayMarks: Bool
    let unfinishedTodos: Int
    let onSelect: () -> Void
    let onOpenTodos: () -> Void
    @State private var isHovered = false
    @Environment(\.calendarPalette) private var palette

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: CalendarTheme.dayLabelSpacing) {
                Text(day.date.day, format: .number.grouping(.never))
                    .font(.system(size: 17, weight: isSelected || day.isToday ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(numberColor)
                if showLunar || day.event != nil {
                    Text(day.subtitle)
                        .font(.system(size: 9, weight: day.event == nil ? .regular : .medium))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(subtitleBackground, in: .rect(cornerRadius: 4))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: CalendarTheme.dayHeight)
            .background(background, in: .rect(cornerRadius: 10))
            .overlay(alignment: .topTrailing) { holidayMark }
            .overlay(alignment: .bottom) { todayIndicator }
            .overlay(alignment: .topLeading) {
                if unfinishedTodos > 0 {
                    Circle().fill(isSelected ? .white : palette.accent)
                        .frame(width: 4, height: 4).padding(.leading, 4).padding(.top, 4)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!CalendarEngine.supportedYears.contains(day.date.year))
        .opacity(day.isCurrentMonth ? 1 : 0.35)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("打开待办"), onOpenTodos)
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if day.holiday?.isOffDay == false { return .primary }
        return day.isWeekend || day.event?.kind == .festival || day.holiday?.isOffDay == true
            ? palette.holiday : .primary
    }

    private var subtitleColor: Color {
        if isSelected { return .white.opacity(0.94) }
        guard let event = day.event else { return .secondary }
        return event.kind == .solarTerm ? palette.solar : palette.holiday
    }

    private var background: Color {
        if isSelected { return palette.selection }
        if day.event?.kind == .festival { return palette.holiday.opacity(0.09) }
        return .primary.opacity(isHovered ? 0.055 : 0)
    }

    private var subtitleBackground: Color {
        guard day.event != nil else { return .clear }
        if isSelected { return .white.opacity(0.16) }
        return day.event?.kind == .solarTerm ? palette.solar.opacity(0.1) : .clear
    }

    @ViewBuilder private var holidayMark: some View {
        if showHolidayMarks, let holiday = day.holiday {
            Text(holiday.isOffDay ? "休" : "班")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(isSelected ? .white.opacity(0.9) : holiday.isOffDay ? palette.holiday : .secondary)
                .padding(.top, 2)
                .padding(.trailing, 3)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var todayIndicator: some View {
        if day.isToday, !isSelected {
            Circle().fill(palette.accent).frame(width: 3, height: 3).offset(y: -1)
        }
    }

    private var accessibilityDescription: String {
        let arrangement = day.holiday.map { "，\($0.name)\($0.isOffDay ? "放假" : "调休上班")" } ?? ""
        return "\(day.date.year)年\(day.date.month)月\(day.date.day)日，\(day.lunar)"
            + (day.event.map { "，\($0.name)" } ?? "") + arrangement + (day.isToday ? "，今天" : "")
            + (unfinishedTodos > 0 ? "，\(unfinishedTodos)项未完成待办" : "") + "，单击选择，双击查看待办"
    }
}
