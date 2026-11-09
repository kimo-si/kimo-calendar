import SwiftUI

struct DayDetailCard: View {
    let model: CalendarModel
    @Environment(\.calendarPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    private var event: String? { model.selectedDay?.event?.name ?? model.selectedDay?.holiday?.name }
    private var isFestival: Bool {
        model.selectedDay?.event?.kind == .festival || model.selectedDay?.holiday?.isOffDay == true
    }
    private var accent: Color { isFestival ? palette.holiday : palette.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.selectedTitle).font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(model.selectedWeekday).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
            Text("农历 " + model.selectedLunar)
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(accent)
            Text(model.selectedLunarYear).font(.system(size: 9)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: event == nil ? "leaf" : isFestival ? "sparkles" : "sun.max")
                Text(event ?? "平常日，也值得期待")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(accent)
            arrangement
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CalendarTheme.detailContentHeight, alignment: .topLeading)
        .padding(CalendarTheme.detailInset)
        .background(alignment: .topTrailing) { SeasonalArtwork(color: accent).opacity(0.22) }
        .background(accent.opacity(0.055), in: .rect(cornerRadius: CalendarTheme.corner))
        .overlay(
            RoundedRectangle(cornerRadius: CalendarTheme.corner).strokeBorder(
                .white.opacity(scheme == .dark ? 0.06 : 0.6)))
    }

    private var arrangement: some View {
        Text(arrangementText)
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var arrangementText: String {
        if let holiday = model.selectedDay?.holiday {
            return holiday.isOffDay ? "\(holiday.name)假期 · 好好休息" : "\(holiday.name)调休 · 今天上班"
        }
        guard model.relevantResult?.data != nil else { return "该年放假安排尚未获取" }
        return model.selectedDay?.isWeekend == true ? "周末 · 给生活留一点空白" : "把每一个今天，过成好日子。"
    }
}

private struct SeasonalArtwork: View {
    let color: Color

    var body: some View {
        Canvas { context, _ in
            var branch = Path()
            branch.move(to: CGPoint(x: 83, y: 0))
            branch.addQuadCurve(to: CGPoint(x: 25, y: 94), control: CGPoint(x: 90, y: 66))
            context.stroke(branch, with: .color(color), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            for index in 0..<5 { drawLeaf(index, context: &context) }
        }
        .frame(width: 90, height: 105)
        .clipped()
        .accessibilityHidden(true)
    }

    // 绘制静态枝叶装饰，不引入图片解码或持续重绘。
    private func drawLeaf(_ index: Int, context: inout GraphicsContext) {
        let x = 74.0 - Double(index) * 7
        let y = 15.0 + Double(index) * 15
        let direction = index.isMultiple(of: 2) ? -1.0 : 1.0
        var leaf = Path()
        leaf.move(to: CGPoint(x: x, y: y))
        leaf.addQuadCurve(
            to: CGPoint(x: x + 24 * direction, y: y - 13), control: CGPoint(x: x + 6 * direction, y: y - 20))
        leaf.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x + 26 * direction, y: y + 7))
        context.fill(leaf, with: .color(color))
    }
}
