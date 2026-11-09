import SwiftUI

enum CalendarStyle: String, CaseIterable, Identifiable, Sendable {
    case lavender, ocean, forest, sakura, apricot, graphite
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lavender: "雾紫"
        case .ocean: "海盐"
        case .forest: "松林"
        case .sakura: "樱粉"
        case .apricot: "暖杏"
        case .graphite: "石墨"
        }
    }
    var palette: CalendarPalette { CalendarPalette(style: self) }
}
