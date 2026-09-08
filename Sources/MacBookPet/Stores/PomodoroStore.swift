import Combine
import Foundation

/// 番茄钟控制器。基于 Timeato 的 PomodoroTimerController 改造：
/// - 加了休息阶段（.running -> .break -> .notRunning）
/// - 用 @MainActor 兼容项目其他 Store
/// - 完成时通过 onComplete 回调通知 UI（给 Cube 联动用）
@MainActor
final class PomodoroStore: ObservableObject {
    enum Phase {
        case focus   // 专注阶段
        case breakTime // 休息阶段
    }

    enum State {
        case notRunning(phase: Phase)
        case running(phase: Phase, endDate: Date, totalTime: TimeInterval)
        case paused(phase: Phase, elapsedTime: TimeInterval, totalTime: TimeInterval)
    }

    private static let focusDurationKey = "MacBookPet.pomodoro.focusMinutes"
    private static let breakDurationKey = "MacBookPet.pomodoro.breakMinutes"

    private let defaults: UserDefaults

    @Published private(set) var state: State
    @Published var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: Self.focusDurationKey) } }
    @Published var breakMinutes: Int { didSet { defaults.set(breakMinutes, forKey: Self.breakDurationKey) } }

    /// 一个完整 focus 阶段结束后触发（不是 break 结束）
    var onFocusComplete: (() -> Void)?

    private var pomodoroTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedFocus = defaults.object(forKey: Self.focusDurationKey) as? Int ?? 25
        let savedBreak = defaults.object(forKey: Self.breakDurationKey) as? Int ?? 5
        self.focusMinutes = max(1, min(120, savedFocus))
        self.breakMinutes = max(1, min(30, savedBreak))
        self.state = .notRunning(phase: .focus)
    }

    private func setState(_ newState: State) {
        state = newState

        pomodoroTimer?.invalidate()
        pomodoroTimer = nil

        if case let .running(_, endDate, _) = newState {
            let timer = Timer(fire: endDate, interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.handleTimerFire()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            pomodoroTimer = timer
        }
    }

    private func handleTimerFire() {
        switch state {
        case .running(let phase, _, _):
            if phase == .focus {
                onFocusComplete?()
                // 自动切到休息阶段
                startBreak()
            } else {
                setState(.notRunning(phase: .focus))
            }
        default:
            break
        }
    }

    // MARK: - Public API

    func start() {
        switch state {
        case .running:
            return
        case .paused(let phase, let elapsed, let total):
            let remaining = total - elapsed
            guard remaining > 0 else {
                setState(.notRunning(phase: phase))
                return
            }
            setState(.running(phase: phase, endDate: Date().addingTimeInterval(remaining), totalTime: total))
        case .notRunning(let phase):
            let minutes = phase == .focus ? focusMinutes : breakMinutes
            let total = TimeInterval(minutes * 60)
            setState(.running(phase: phase, endDate: Date().addingTimeInterval(total), totalTime: total))
        }
    }

    func startBreak() {
        let total = TimeInterval(breakMinutes * 60)
        setState(.running(phase: .breakTime, endDate: Date().addingTimeInterval(total), totalTime: total))
    }

    func pause() {
        guard case .running(let phase, _, let total) = state,
              let elapsed = elapsedTime else { return }
        setState(.paused(phase: phase, elapsedTime: elapsed, totalTime: total))
    }

    func stop() {
        let phase: Phase = currentPhase
        setState(.notRunning(phase: phase))
    }

    /// 用户手动切换阶段（仅在未跑未暂停时生效）
    func switchPhase(to phase: Phase) {
        guard !isRunning && !isPaused else { return }
        setState(.notRunning(phase: phase))
    }

    // MARK: - Computed

    var currentPhase: Phase {
        switch state {
        case .notRunning(let phase),
             .running(let phase, _, _),
             .paused(let phase, _, _):
            return phase
        }
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    var elapsedTime: TimeInterval? {
        switch state {
        case .running(_, let endDate, let total):
            return total - endDate.timeIntervalSinceNow
        case .paused(_, let elapsed, _):
            return elapsed
        case .notRunning:
            return nil
        }
    }

    var remainingTime: TimeInterval? {
        switch state {
        case .running(_, let endDate, _):
            return max(0, endDate.timeIntervalSinceNow)
        case .paused(_, let elapsed, let total):
            return max(0, total - elapsed)
        case .notRunning:
            return nil
        }
    }

    var progress: Double {
        switch state {
        case .running(_, _, let total), .paused(_, _, let total):
            guard let elapsed = elapsedTime, total > 0 else { return 0 }
            return min(1, max(0, elapsed / total))
        case .notRunning:
            return 0
        }
    }
}
