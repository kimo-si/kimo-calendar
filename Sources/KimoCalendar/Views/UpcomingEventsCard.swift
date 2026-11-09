import SwiftUI

struct UpcomingEventsCard: View {
    let model: CalendarModel
    @Environment(\.calendarPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").foregroundStyle(palette.accent.opacity(0.8))
                Text("近期节日 · 节气").fontWeight(.semibold)
            }
            .font(.system(size: 11))
            Divider().opacity(0.5)
            ForEach(model.upcoming) { event in
                HStack(spacing: 5) {
                    Text(event.name).fontWeight(.medium).frame(width: 31, alignment: .leading)
                    Text("\(event.date.month)月\(event.date.day)日").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    let days = model.countdown(event)
                    Text(days == 0 ? "今天" : "\(days)天后")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(palette.accent.opacity(0.09), in: .rect(cornerRadius: 5))
                }
                .font(.system(size: 9))
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CalendarTheme.detailContentHeight, alignment: .topLeading)
        .padding(CalendarTheme.detailInset)
        .background(.background.opacity(0.44), in: .rect(cornerRadius: CalendarTheme.corner))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("从今天起的近期节日与节气")
    }
}
