import Foundation

public struct SolarTermCalculator: Sendable {
    private let engine: CalendarEngine
    private static let unixJulianDay = 2_440_587.5
    private static let secondsPerDay = 86_400.0
    private static let names = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
        "立夏", "小满", "芒种", "夏至", "小暑", "大暑", "立秋", "处暑",
        "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至",
    ]

    // 在同一民用时区将太阳黄经时刻映射为节气日期。
    public init(engine: CalendarEngine) { self.engine = engine }

    // 逐个求解太阳视黄经每隔十五度的时刻，避免固定节气日期表。
    public func events(year: Int) -> [CalendarEvent] {
        Self.names.enumerated().map { index, name in
            let instant = instant(year: year, index: index)
            return CalendarEvent(date: engine.civilDate(instant), name: name, kind: .solarTerm)
        }
    }

    // 使用儒略日迭代求解节气，1901—2099 年按近似 ΔT 修正到 UTC。
    private func instant(year: Int, index: Int) -> Date {
        let january = engine.date(CivilDate(year: year, month: 1, day: 5))
        var julian = january.timeIntervalSince1970 / Self.secondsPerDay + Self.unixJulianDay
        julian += Double(index) * 365.2422 / 24
        let target = (285 + Double(index) * 15).truncatingRemainder(dividingBy: 360)
        for _ in 0..<6 {
            let error = normalized(longitude(julian) - target + 180) - 180
            julian -= error / 0.98564736
        }
        let deltaT = 62.92 + 0.32217 * Double(year - 2000) + 0.005589 * pow(Double(year - 2000), 2)
        return Date(timeIntervalSince1970: (julian - Self.unixJulianDay) * Self.secondsPerDay - deltaT)
    }

    // 按太阳平黄经、中心差和章动近似计算太阳视黄经。
    private func longitude(_ julian: Double) -> Double {
        let t = (julian - 2_451_545) / 36_525
        let meanLongitude = 280.46646 + 36_000.76983 * t + 0.0003032 * t * t
        let anomaly = radians(357.52911 + 35_999.05029 * t - 0.0001537 * t * t)
        let center =
            (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(anomaly)
            + (0.019993 - 0.000101 * t) * sin(2 * anomaly) + 0.000289 * sin(3 * anomaly)
        return normalized(meanLongitude + center - 0.00569 - 0.00478 * sin(radians(125.04 - 1934.136 * t)))
    }

    // 将角度转换为三角函数使用的弧度。
    private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    // 将角度归一到零至三百六十度，保证跨零点迭代稳定。
    private func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
