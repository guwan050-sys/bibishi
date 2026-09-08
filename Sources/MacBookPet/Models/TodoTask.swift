import Foundation

struct TodoTask: Identifiable, Codable, Equatable {
    /// 提前提醒的分钟数。0 = 到点提醒（不提前）。
    enum LeadTime: Int, CaseIterable, Codable {
        case none = 0
        case minutes5 = 5
        case minutes10 = 10
        case minutes15 = 15
        case minutes30 = 30

        var label: String {
            switch self {
            case .none: return "到点提醒"
            case .minutes5: return "提前 5 分钟"
            case .minutes10: return "提前 10 分钟"
            case .minutes15: return "提前 15 分钟"
            case .minutes30: return "提前 30 分钟"
            }
        }
    }

    /// 任务循环规则。完成时如果 rule != .none，自动生成下一条。
    enum RepeatRule: String, CaseIterable, Codable {
        case none
        case daily       // 每天
        case weekly      // 每周同一天
        case weekdays    // 仅工作日（周一 ~ 周五）

        var label: String {
            switch self {
            case .none: return "不循环"
            case .daily: return "每天"
            case .weekly: return "每周"
            case .weekdays: return "工作日"
            }
        }

        /// 给定当前到期日，返回下一次到期日。无下一次返回 nil。
        /// 重要：返回的日期保持原 hour/minute，只调整 day。
        func nextOccurrence(after current: Date) -> Date? {
            let cal = Calendar.current
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: current)
            guard let baseDay = cal.date(from: comps) else { return nil }

            switch self {
            case .none:
                return nil
            case .daily:
                return cal.date(byAdding: .day, value: 1, to: baseDay)
            case .weekly:
                return cal.date(byAdding: .day, value: 7, to: baseDay)
            case .weekdays:
                // 周六 (7)、周日 (1) 跳到周一；其余 +1 天
                var next = cal.date(byAdding: .day, value: 1, to: baseDay) ?? baseDay
                var weekday = cal.component(.weekday, from: next)
                while weekday == 1 || weekday == 7 {
                    next = cal.date(byAdding: .day, value: 1, to: next) ?? next
                    weekday = cal.component(.weekday, from: next)
                }
                return next
            }
        }
    }

    let id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var leadTime: LeadTime
    var repeatRule: RepeatRule
    var reminderFired: Bool
    var isDone: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        leadTime: LeadTime = .none,
        repeatRule: RepeatRule = .none,
        reminderFired: Bool = false,
        isDone: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.leadTime = leadTime
        self.repeatRule = repeatRule
        self.reminderFired = reminderFired
        self.isDone = isDone
        self.createdAt = createdAt
    }

    // MARK: - Codable（手动 init(from:) 兼容旧数据）
    // 旧版本 TodoTask 没有 leadTime / repeatRule 字段；
    // 用 decodeIfPresent 防止旧 JSON 直接解析失败把整个任务列表弄丢。

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, dueDate, leadTime, repeatRule, reminderFired, isDone, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        self.leadTime = try c.decodeIfPresent(LeadTime.self, forKey: .leadTime) ?? .none
        self.repeatRule = try c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule) ?? .none
        self.reminderFired = try c.decodeIfPresent(Bool.self, forKey: .reminderFired) ?? false
        self.isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    // MARK: - Computed

    var hasReminder: Bool {
        dueDate != nil
    }

    /// 任务到点未完成且未 dismiss。注意：
    /// 1. reminderFired = true 表示"用户已点 × 或已发过通知，本次不再提醒"
    /// 2. 持久化 reminderFired：跨 app 重启保留，避免重启后反复弹同一个过期任务
    /// 3. 用户想恢复提醒：编辑任务改一下 dueDate 即可（update 时会重置 reminderFired）
    var isOverdue: Bool {
        guard let dueDate, !isDone, !reminderFired else { return false }
        return dueDate < Date()
    }

    /// 实际触发提醒的日期 = dueDate - leadTime。给 scheduleReminder 用。
    var reminderFireDate: Date? {
        guard let dueDate else { return nil }
        return dueDate.addingTimeInterval(-TimeInterval(leadTime.rawValue * 60))
    }
}
