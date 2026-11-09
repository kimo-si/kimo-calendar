import KimoCalendarCore
import SwiftUI

struct MonthPickerView: View {
    let model: CalendarModel
    @State private var selectedYear: Int
    @Environment(\.calendarPalette) private var palette
    private static let columns = Array(repeating: GridItem(.fixed(65)), count: 3)

    // 选择器每次打开时使用当前显示年份，而非系统当前年。
    init(model: CalendarModel) {
        self.model = model
        _selectedYear = State(initialValue: model.year)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("上一年", systemImage: "chevron.left") { selectedYear -= 1 }
                    .disabled(selectedYear <= CalendarEngine.supportedYears.lowerBound)
                Spacer()
                Text("\(selectedYear.formatted(.number.grouping(.never)))年").font(.headline).monospacedDigit()
                Spacer()
                Button("下一年", systemImage: "chevron.right") { selectedYear += 1 }
                    .disabled(selectedYear >= CalendarEngine.supportedYears.upperBound)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(ToolbarButtonStyle())
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(1...12, id: \.self) { month in
                    Button("\(month)月") { model.jump(year: selectedYear, month: month) }
                        .buttonStyle(.plain)
                        .frame(width: 65, height: 32)
                        .background(
                            model.month == month && model.year == selectedYear
                                ? palette.accent.opacity(0.13) : .clear, in: .rect(cornerRadius: 7))
                }
            }
        }
        .padding(16)
        .frame(width: 237)
        .tint(palette.accent)
    }
}
