import AppKit
import AVFoundation
import Combine
import Foundation
import UserNotifications

@MainActor
final class TodoStore: ObservableObject {
    private static let tasksKey = "MacBookPet.todoTasks"
    private static let soundKey = "MacBookPet.todo.soundEnabled"
    private static let notificationIdentifierPrefix = "MacBookPet.todo."

    // 通知 category / action id
    nonisolated static let categoryIdentifier = "MacBookPet.todo.category"
    nonisolated static let snoozeActionId = "MacBookPet.todo.action.snooze"
    nonisolated static let completeActionId = "MacBookPet.todo.action.complete"
    nonisolated static let taskIDUserInfoKey = "taskID"

    @Published private(set) var tasks: [TodoTask] = []

    /// Fires after a notification has been posted so the menu/UI can flash a
    /// badge or play a one-shot speech line.
    @Published private(set) var lastFiredTaskID: UUID?

    /// 待办提醒是否同时播放提示音。由待办窗口里的开关控制。
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Self.soundKey) }
    }

    var onChange: (() -> Void)?

    private let defaults: UserDefaults
    private let notificationCenter = UNUserNotificationCenter.current()
    private nonisolated let nonisolatedNotificationCenter = UNUserNotificationCenter.current()
    private var scanTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.soundEnabled = defaults.bool(forKey: Self.soundKey)
        load()
        // reminderFired 不应该跨启动持久化：之前启动时如果系统通知没真的弹出（权限拒绝、app 被强杀等），
        // 重启后这个标志会让 scanOverdue 跳过这些任务，永远不再提醒。
        // 重置策略：已经过期的任务重新标记为未触发，等下次扫描触发气泡。
        // 注意：这里"过期 = dueDate < now"，所以 leadTime 提前到点的不算过期（要严格 > now）——保留
        // 提前提醒的能力。
        let now = Date()
        for index in tasks.indices where tasks[index].reminderFired {
            if let due = tasks[index].dueDate, due <= now, !tasks[index].isDone {
                tasks[index].reminderFired = false
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        // 用户决策：只走桌宠气泡，不要系统通知 banner。
        // 因此不调 registerNotificationCategories / requestAuthorizationIfNeeded /
        // rescheduleAllReminders —— 这些函数仍然保留（scheduleReminder/cancelReminder/handleNotificationAction
        // 等未删除），未来想恢复系统通知只需取消下面三行的注释并加回 MacBookPetApp 的
        // UNUserNotificationCenterDelegate。App 不在跑时不会响——这是用户接受的成本。
        //
        // registerNotificationCategories()
        // requestAuthorizationIfNeeded()
        // rescheduleAllReminders()
        startScanTimer()
        scanOverdue()
    }

    func stop() {
        scanTimer?.invalidate()
        scanTimer = nil
        persist()
    }

    // MARK: - CRUD

    func add(_ task: TodoTask) {
        tasks.append(task)
        sortInPlace()
        scheduleReminder(for: task)
        if task.isOverdue {
            scanOverdue()
        }
        persist()
        onChange?()
    }

    func update(_ task: TodoTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let old = tasks[index]
        tasks[index] = task
        cancelReminder(for: old)
        // 改了 dueDate / repeatRule / isDone 任意一个 → 重新调度，且重置 reminderFired
        // 让用户能"编辑一下就重新启用提醒"。
        let needsReschedule = old.dueDate != task.dueDate
            || old.repeatRule != task.repeatRule
            || old.leadTime != task.leadTime
            || old.isDone != task.isDone
        if needsReschedule && !task.isDone {
            tasks[index].reminderFired = false
            scheduleReminder(for: tasks[index])
        }
        persist()
        onChange?()
        if task.isOverdue {
            scanOverdue()
        }
    }

    func remove(id: UUID) {
        if let task = tasks.first(where: { $0.id == id }) {
            cancelReminder(for: task)
        }
        tasks.removeAll { $0.id == id }
        persist()
        onChange?()
    }

    func toggleDone(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isDone.toggle()
        let nowDone = tasks[index].isDone
        if nowDone {
            cancelReminder(for: tasks[index])
            // repeat 续期：完成后用 repeatRule 算出下一次到期日，生成一条新任务。
            // 注意：旧任务保留 isDone=true，方便"已完成"视图查看。
            if tasks[index].repeatRule != .none,
               let due = tasks[index].dueDate,
               let nextDue = tasks[index].repeatRule.nextOccurrence(after: due) {
                let nextTask = TodoTask(
                    title: tasks[index].title,
                    notes: tasks[index].notes,
                    dueDate: nextDue,
                    leadTime: tasks[index].leadTime,
                    repeatRule: tasks[index].repeatRule,
                    isDone: false
                )
                tasks.append(nextTask)
                scheduleReminder(for: nextTask)
            }
        } else {
            // 取消完成 → 重新调度，且重置 reminderFired 让它能再响
            tasks[index].reminderFired = false
            scheduleReminder(for: tasks[index])
        }
        sortInPlace()
        persist()
        onChange?()
    }

    func pendingTasks() -> [TodoTask] {
        tasks.filter { !$0.isDone }
    }

    /// 待办窗口用的视图过滤。
    enum ViewFilter: String, CaseIterable, Identifiable {
        case today
        case all
        case done
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: return "今天"
            case .all: return "全部"
            case .done: return "已完成"
            }
        }
    }

    func tasks(for filter: ViewFilter) -> [TodoTask] {
        switch filter {
        case .today:
            let cal = Calendar.current
            return tasks.filter { task in
                guard !task.isDone else { return false }
                guard let due = task.dueDate else { return false }
                return cal.isDateInToday(due) || due < Date()
            }
        case .all:
            return tasks.filter { !$0.isDone }
        case .done:
            return tasks.filter { $0.isDone }
        }
    }

    // MARK: - Reminder scheduler

    private func scheduleReminder(for task: TodoTask) {
        guard let fireDate = task.reminderFireDate, !task.isDone, !task.reminderFired else { return }
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "待办提醒"
        content.body = task.title
        content.sound = soundEnabled ? .default : nil
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [Self.taskIDUserInfoKey: task.id.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        // 关键：UNCalendarNotificationTrigger 用绝对时刻，跨重启 / app 被杀 / 系统 sleep 后醒来仍能 fire
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifierPrefix + task.id.uuidString,
            content: content,
            trigger: trigger
        )
        nonisolatedNotificationCenter.add(request) { _ in }
    }

    private func cancelReminder(for task: TodoTask) {
        nonisolatedNotificationCenter.removePendingNotificationRequests(
            withIdentifiers: [Self.notificationIdentifierPrefix + task.id.uuidString]
        )
    }

    private func rescheduleAllReminders() {
        nonisolatedNotificationCenter.removeAllPendingNotificationRequests()
        for task in tasks where !task.isDone {
            scheduleReminder(for: task)
        }
    }

    private func startScanTimer() {
        scanTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanOverdue()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scanTimer = timer
    }

    /// In-app fallback: 如果系统通知没真的弹出（权限拒绝、app 被强杀、timeSensitive 不允许等），
    /// 这个 30s 扫一次还能在桌宠气泡里给用户看。
    /// reminderFired = true 是"本条任务已提醒过"标记，防止无限重弹。
    private func scanOverdue() {
        let now = Date()
        var didFire = false
        for index in tasks.indices where !tasks[index].isDone && !tasks[index].reminderFired {
            // 用 reminderFireDate（考虑 leadTime 提前量）作为触发点
            guard let fire = tasks[index].reminderFireDate, fire <= now else { continue }
            tasks[index].reminderFired = true
            lastFiredTaskID = tasks[index].id
            if soundEnabled {
                playReminderSound()
            }
            didFire = true
        }
        if didFire {
            persist()
            onChange?()
        }
    }

    // MARK: - 公共 action 入口（UI / 通知 action 都会调到这）

    /// 通知 action 路由入口。从通知 banner 点的 "5min 后再提醒" / "已完成" 走到这里。
    /// 必须在主线程上调用（category / action 都是系统回调，注意 dispatch）。
    func handleNotificationAction(_ actionId: String, taskID: UUID) {
        switch actionId {
        case Self.snoozeActionId:
            snoozeReminder(taskID: taskID, minutes: 5)
        case Self.completeActionId:
            toggleDone(id: taskID)
        default:
            break
        }
    }

    /// 用户从桌宠气泡点 × 调到这里。
    /// 语义：本次不再提醒（reminderFired = true），任务保留未完成。
    /// 配合"本次永远不重提"决策。
    func dismissReminder(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard !tasks[index].reminderFired else { return }
        tasks[index].reminderFired = true
        persist()
    }

    /// snooze n 分钟。把 dueDate 推后 n 分钟，重新调度一条。
    /// 注意：dueDate 会被改写——这会影响 repeat 续期（nextOccurrence 基于新 dueDate 算）。
    /// 对一次性任务这是合理的；对 repeat 任务，用户应该先去原到期日做完再 snooze，
    /// 如果真要 snooze 循环任务，下次循环也会按这个新 dueDate 推——可接受。
    func snoozeReminder(taskID: UUID, minutes: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard !tasks[index].isDone else { return }
        let now = Date()
        let newDue = now.addingTimeInterval(TimeInterval(minutes * 60))
        tasks[index].dueDate = newDue
        tasks[index].reminderFired = false
        cancelReminder(for: tasks[index])
        scheduleReminder(for: tasks[index])
        sortInPlace()
        persist()
        onChange?()
    }

    // MARK: - Authorization & Categories

    private func registerNotificationCategories() {
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionId,
            title: "5 分钟后再提醒",
            options: []
        )
        let complete = UNNotificationAction(
            identifier: Self.completeActionId,
            title: "已完成",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [snooze, complete],
            intentIdentifiers: [],
            options: []
        )
        nonisolatedNotificationCenter.setNotificationCategories([category])
    }

    private func requestAuthorizationIfNeeded() {
        nonisolatedNotificationCenter.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .notDetermined:
                self.nonisolatedNotificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
            default:
                break
            }
        }
    }

    // MARK: - Sound

    private func playReminderSound() {
        // 优先用 NSSound（系统音）—— 比 AVAudioPlayer 轻量，且 macOS 原生。
        // 失败 fallback 到 NSSound.beep()。
        let candidates = ["Ping", "Glass", "Tink", "Pop", "Frog"]
        for name in candidates {
            if let sound = NSSound(named: NSSound.Name(name)) {
                sound.play()
                return
            }
        }
        NSSound.beep()
    }

    // MARK: - Persistence

    private func sortInPlace() {
        tasks.sort { lhs, rhs in
            if lhs.isDone != rhs.isDone {
                return !lhs.isDone
            }
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?): return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.createdAt < rhs.createdAt
            }
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.tasksKey),
              let decoded = try? JSONDecoder().decode([TodoTask].self, from: data)
        else { return }
        tasks = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        defaults.set(data, forKey: Self.tasksKey)
    }
}
