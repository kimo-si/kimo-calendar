import Foundation

public struct CalendarEvent: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case festival, solarTerm }
    public let date: CivilDate
    public let name: String
    public let kind: Kind
    public var id: String { date.iso8601 + name }

    // 创建具有稳定标识的节日或节气。
    public init(date: CivilDate, name: String, kind: Kind) {
        self.date = date
        self.name = name
        self.kind = kind
    }
}
