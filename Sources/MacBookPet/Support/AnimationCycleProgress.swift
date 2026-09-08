import Foundation
import CoreGraphics

/// 共享的「周期 + 延迟 + 持续时间」动画进度计算，用于循环浮起元素（音符、气泡等）。
enum AnimationCycleProgress {
    /// 返回当前在循环周期内的归一化进度。
    ///
    /// - 周期从 `date.timeIntervalSinceReferenceDate` 取模 `cycle` 得到 `localTime`。
    /// - `localTime < delay` 时为 0（尚未开始）。
    /// - `localTime - delay > duration` 时为 0（本次循环已结束）。
    /// - 否则返回 `[0, 1]` 之间的活跃进度。
    static func value(at date: Date, delay: TimeInterval, duration: TimeInterval, cycle: TimeInterval) -> CGFloat {
        let localTime = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        guard localTime >= delay else { return 0 }

        let activeTime = localTime - delay
        guard activeTime <= duration else { return 0 }

        return CGFloat(min(max(activeTime / duration, 0), 1))
    }
}
