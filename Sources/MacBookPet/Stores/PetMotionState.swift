import CoreGraphics
import Foundation

struct ExperienceGainEffect: Identifiable, Equatable {
    let id = UUID()
    let amount: Int
}

struct SatietyGainEffect: Identifiable, Equatable {
    let id = UUID()
    let amount: Int
}

/// 工作状态的可爱表情气泡（Cube 专注、喝咖啡、记笔记…）
struct PetWorkingBubble: Identifiable, Equatable {
    enum Mood: String {
        case focusing    // 🛠️ 专注敲键盘
        case sipping     // ☕️ 喝咖啡
        case note        // ✏️ 记笔记
        case idea        // 💡 想到主意
        case celebrating // 🎉 完成庆祝
        case reminder    // ⏰ 待办提醒

        var symbol: String {
            switch self {
            case .focusing: return "hammer.fill"
            case .sipping: return "cup.and.saucer.fill"
            case .note: return "pencil.and.list.clipboard"
            case .idea: return "lightbulb.fill"
            case .celebrating: return "party.popper.fill"
            case .reminder: return "bell.badge.fill"
            }
        }
    }

    let id = UUID()
    let mood: Mood
    let text: String?
    /// 关联的待办 taskID。nil 表示非待办气泡（专注/喝咖啡/庆祝等），
    /// 此时点 × 按钮不会出现"标记完成/已知道"等操作。
    let taskID: UUID?
}

@MainActor
final class PetMotionState: ObservableObject {
    @Published var rotationDegrees: CGFloat = 0
    @Published var stretchX: CGFloat = 1
    @Published var stretchY: CGFloat = 1
    @Published var gazeOffset: CGSize = .zero
    @Published var feedMouthOpen: CGFloat = 0
    @Published var isGrabbed = false
    // NOTE: hop offsets are no longer stored as @Published. They are derived
    // per-frame from `hopOffsets(at:traveling:)` and passed directly to the
    // SwiftUI view. Writing @Published from inside a TimelineView body
    // creates a re-entrant update cycle that pegs the main thread at 100%
    // CPU (TimelineView tick → @Published setter → ObservableObject.send →
    // invalidateAttribute → same TimelineView re-evaluates → another
    // @Published setter → 100% CPU). Keep these values local to the view.
    @Published private(set) var experienceGainEffect: ExperienceGainEffect?
    @Published private(set) var satietyGainEffect: SatietyGainEffect?
    @Published private(set) var workingBubble: PetWorkingBubble?

    private var experienceGainTask: Task<Void, Never>?
    private var satietyGainTask: Task<Void, Never>?
    private var workingBubbleTask: Task<Void, Never>?

    @discardableResult
    func updateMotionTransform(
        rotationDegrees: CGFloat,
        stretchX: CGFloat,
        stretchY: CGFloat,
        tolerance: CGFloat = 0.0001
    ) -> Bool {
        var didChange = false

        if abs(self.rotationDegrees - rotationDegrees) > tolerance {
            self.rotationDegrees = rotationDegrees
            didChange = true
        }
        if abs(self.stretchX - stretchX) > tolerance {
            self.stretchX = stretchX
            didChange = true
        }
        if abs(self.stretchY - stretchY) > tolerance {
            self.stretchY = stretchY
            didChange = true
        }

        return didChange
    }

    func showExperienceGain(_ amount: Int) {
        guard amount > 0 else { return }

        experienceGainTask?.cancel()
        experienceGainTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }

            let effect = ExperienceGainEffect(amount: amount)
            self?.experienceGainEffect = effect

            try? await Task.sleep(nanoseconds: 1_250_000_000)
            guard !Task.isCancelled, self?.experienceGainEffect?.id == effect.id else { return }
            self?.experienceGainEffect = nil
        }
    }

    func showSatietyGain(_ amount: Int) {
        guard amount > 0 else { return }

        satietyGainTask?.cancel()
        satietyGainTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }

            let effect = SatietyGainEffect(amount: amount)
            self?.satietyGainEffect = effect

            try? await Task.sleep(nanoseconds: 1_250_000_000)
            guard !Task.isCancelled, self?.satietyGainEffect?.id == effect.id else { return }
            self?.satietyGainEffect = nil
        }
    }

    /// 显示工作表情气泡。duration 传 nil 则一直显示直到手动清除。
    /// taskID 用于待办提醒气泡：传进 taskID 后，bubble 上的 × / 已完成 按钮能反向找到原 task。
    func showWorkingBubble(
        mood: PetWorkingBubble.Mood,
        text: String? = nil,
        duration: TimeInterval? = nil,
        taskID: UUID? = nil
    ) {
        workingBubbleTask?.cancel()
        let bubble = PetWorkingBubble(mood: mood, text: text, taskID: taskID)
        workingBubble = bubble

        guard let duration else { return }
        workingBubbleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard self?.workingBubble?.id == bubble.id else { return }
            self?.workingBubble = nil
        }
    }

    func clearWorkingBubble() {
        workingBubbleTask?.cancel()
        workingBubbleTask = nil
        workingBubble = nil
    }

    /// 桌宠气泡的"我知道了"按钮：仅当当前气泡是 taskID 匹配的待办气泡时清掉。
    /// 不带 taskID 的气泡（专注 / 庆祝等）保持不变——它们有自己的生命周期。
    /// 带 taskID 但不匹配时也保持不变——避免 race 条件下错清（多个待办连续到点）。
    func dismissReminderBubble(taskID: UUID) {
        guard let current = workingBubble, current.taskID == taskID else { return }
        workingBubbleTask?.cancel()
        workingBubbleTask = nil
        workingBubble = nil
    }

    /// 桌宠气泡的"已完成"按钮：taskID 匹配时清掉气泡。
    /// todoStore.toggleDone 由调用方负责，本方法只管清气泡。
    func completeReminderBubble(taskID: UUID) {
        guard let current = workingBubble, current.taskID == taskID else { return }
        workingBubbleTask?.cancel()
        workingBubbleTask = nil
        workingBubble = nil
    }

    /// Computes the bounce/sway offsets for the current frame. Pure function —
    /// the caller is expected to pass the returned values directly into
    /// SwiftUI modifiers (`.offset`, `.rotationEffect`), NOT into a
    /// @Published property. Writing these into @Published from inside a
    /// TimelineView body creates a re-entrant update cycle that pegs the
    /// main thread at 100% CPU. See the NOTE above the @Published block.
    /// - Returns: `(x, y, rotation)` in points / degrees. All zero when
    ///   `traveling` is false.
    func hopOffsets(at date: Date, traveling: Bool) -> (x: CGFloat, y: CGFloat, rotation: CGFloat) {
        guard traveling else { return (0, 0, 0) }
        let t = date.timeIntervalSinceReferenceDate
        // Bounce: only positive half of sin wave, shifted so the pet sits
        // at the apex. ~6 hops/sec, ~8pt lift.
        return (
            x: sin(t * 2.0) * 2,
            y: -abs(sin(t * 6.0)) * 8,
            rotation: sin(t * 6.0) * 8
        )
    }

    /// 桌宠头顶工作气泡的点击命中区（**AppKit 窗口坐标系**：y 从下往上
    /// 增长，对得上 `NSEvent.locationInWindow`）。没有气泡时返回 nil。
    ///
    /// 用于 PetPhysicsController 在 beginDrag 时判断本次点击是否落在气泡
    /// 上——是的话就跳过拖拽 setup、记下 isMouseDownOnBubble，endDrag 会
    /// 拿它去 fire onBubbleClick。不走 NSHostingView 的 SwiftUI hit-testing。
    ///
    /// 故意比气泡可视区域大一圈：气泡内容宽度会随文字长度变化，给个宽容
    /// 的固定命中区，让"点气泡"这个交互更容易命中。
    ///
    /// 坐标系一定要用 AppKit 的：PetView.swift 里 bubbleY 是 SwiftUI 坐标
    /// （y 从上往下），要转成 AppKit 坐标用 `canvasHeight - swiftUI_y`。
    /// 之前没转就拿去跟 locationInWindow 比，hit test 永远 false。
    var bubbleHitTestFrame: CGRect? {
        guard workingBubble != nil else { return nil }
        // SwiftUI 坐标下的 bubble 中心 y（从顶往下算）
        let bubbleCenterYSwiftUI = PetMetrics.canvasHeight
            - PetMetrics.bodyInsetY
            - PetMetrics.bodySize
            - 18
        // 翻成 AppKit 坐标（从底往上算）
        let bubbleCenterY = PetMetrics.canvasHeight - bubbleCenterYSwiftUI
        let width: CGFloat = 130
        let height: CGFloat = 56
        return CGRect(
            x: PetMetrics.canvasWidth / 2 - width / 2,
            y: bubbleCenterY - height / 2,
            width: width,
            height: height
        )
    }

}
