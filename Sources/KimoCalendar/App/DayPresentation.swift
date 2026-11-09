import Foundation
import KimoCalendarCore

struct DayPresentation: Identifiable, Equatable {
    let date: CivilDate
    let instant: Date
    let lunar: String
    let event: CalendarEvent?
    let holiday: HolidayDay?
    let isCurrentMonth: Bool
    let isToday: Bool
    let isWeekend: Bool
    var id: CivilDate { date }
    var subtitle: String { event?.name ?? lunar }
}
