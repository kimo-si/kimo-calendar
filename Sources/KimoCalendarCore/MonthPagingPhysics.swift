import Foundation

public enum MonthPagingPhysics {
    public static let minimumDuration = 0.16
    public static let maximumDuration = 0.30
    private static let commitFraction = 0.24
    private static let flickFraction = 0.45
    private static let minimumFlickTravel = 24.0
    private static let edgeResistance = 0.22

    // 根据实际距离或抬手预测决定翻一页，轻扫不足时回到当前月份。
    public static func destination(
        distance: Double, projected: Double, width: Double, canGoBack: Bool, canGoForward: Bool
    ) -> Int {
        guard width.isFinite, width > 0, distance.isFinite, projected.isFinite else { return 0 }
        let travel = abs(distance) >= width * commitFraction ? distance : projected
        let isFlick = abs(distance) >= min(minimumFlickTravel, width * 0.1) && abs(projected) >= width * flickFraction
        guard abs(distance) >= width * commitFraction || isFlick else { return 0 }
        let step = travel < 0 ? 1 : -1
        return step > 0 ? (canGoForward ? step : 0) : (canGoBack ? step : 0)
    }

    // 拖动期间保持一比一跟手，年份边界使用有限阻力且不露出空白页。
    public static func displacement(
        _ distance: Double, width: Double, canGoBack: Bool, canGoForward: Bool
    ) -> Double {
        guard width.isFinite, width > 0, distance.isFinite else { return 0 }
        let bounded = min(width, max(-width, distance))
        let blocked = bounded > 0 ? !canGoBack : !canGoForward
        return blocked ? bounded * edgeResistance / (1 + abs(bounded) / 32) : bounded
    }

    // 剩余行程较短时缩短吸附时间，页面不会在松手后重新滑动完整一程。
    public static func duration(from offset: Double, to target: Double, width: Double) -> Double {
        guard width.isFinite, width > 0, offset.isFinite, target.isFinite else { return minimumDuration }
        return min(maximumDuration, max(minimumDuration, abs(target - offset) / width * maximumDuration))
    }
}
